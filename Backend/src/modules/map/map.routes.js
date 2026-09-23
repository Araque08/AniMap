const express = require('express');
const { ObjectId } = require('mongodb');
const pool = require('../../config/postgres_db');
const { getMongoDb } = require('../../config/mongo_db');
const optionalAuthMiddleware = require('../../middleware/optional-auth.middleware');

const router = express.Router();

router.get('/images/:imageId', async (req, res) => {
  const imageId = req.params.imageId;
  if (!ObjectId.isValid(imageId)) {
    return res.status(400).json({ ok: false, message: 'ID de imagen inválido' });
  }

  try {
    const reference = await pool.query(
      `SELECT f.fk_mascota
       FROM foto_mascota f
       INNER JOIN reporte r ON r.fk_mascota = f.fk_mascota
       INNER JOIN mascota m ON m.id = f.fk_mascota
       WHERE f.storage_ref = $1
         AND ((r.estado = 'ACTIVO' AND m.estado = 'PERDIDA')
           OR (r.estado = 'FINALIZADO'
             AND m.estado <> 'INACTIVA'
             AND r.cerrado_en >=
               (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '30 days'))
       LIMIT 1`,
      [imageId]
    );
    if (reference.rowCount === 0) {
      return res.status(404).json({ ok: false, message: 'Imagen no encontrada' });
    }

    const db = await getMongoDb();
    const image = await db.collection('ImagenMascota').findOne({
      _id: new ObjectId(imageId),
      mascotaIdPg: reference.rows[0].fk_mascota,
      estado: 'ACTIVA',
    });
    const content = image?.imagen || image?.buffer;
    const payload = Buffer.isBuffer(content)
      ? content
      : content?.buffer
        ? Buffer.from(content.buffer)
        : null;
    if (!payload) {
      return res.status(404).json({ ok: false, message: 'Imagen no encontrada' });
    }

    res.set('Content-Type', image.mimeType || 'application/octet-stream');
    res.set('Cache-Control', 'public, max-age=3600');
    return res.send(payload);
  } catch (error) {
    console.error('Error consultando imagen pública del reporte:', error);
    return res.status(500).json({ ok: false, message: 'Error consultando la imagen' });
  }
});

/*
  GET /api/map/reports

  Esta ruta entrega al mapa los datos que antes estaban quemados en Flutter.
  Por ahora consulta PostgreSQL y arma una respuesta lista para pintar:
  - Mascotas perdidas: vienen de reporte + mascota + ubicación.
  - Avistamientos: vienen de avistamiento + ubicación.

  Más adelante se puede ampliar para filtros por radio, especie, raza o fecha.
*/
router.get('/reports', optionalAuthMiddleware, async (req, res) => {
  try {
    /*
      Reportes activos de mascotas perdidas.
    */
    const reportesResult = await pool.query(`
      SELECT
        r.id AS reporte_id,
        r.descripcion AS reporte_descripcion,
        r.estado AS reporte_estado,
        to_char((r.creado_en AT TIME ZONE 'UTC') AT TIME ZONE 'America/Bogota',
          'YYYY-MM-DD"T"HH24:MI:SS.MS') || '-05:00' AS creado_en,
        CASE WHEN r.cerrado_en IS NULL THEN NULL
          ELSE to_char((r.cerrado_en AT TIME ZONE 'UTC') AT TIME ZONE 'America/Bogota',
            'YYYY-MM-DD"T"HH24:MI:SS.MS') || '-05:00'
        END AS cerrado_en,
        r.mostrar_contacto,
        r.fk_usuario AS report_owner_id,

        m.id AS mascota_id,
        m.nombre AS mascota_nombre,
        m.color AS mascota_color,
        m.sexo AS mascota_sexo,
        m.estado AS mascota_estado,

        e.nombre AS especie_nombre,
        raza.nombre AS raza_nombre,

        CASE
          WHEN r.mostrar_contacto = TRUE THEN u.telefono
          ELSE NULL
        END AS owner_phone,

        ub.metodo,
        ub.lat,
        ub.lng,
        ub.direccion,
        photos.foto_storage_ref,
        photos.foto_storage_refs
      FROM reporte r
      INNER JOIN mascota m
        ON m.id = r.fk_mascota
      INNER JOIN especie e
        ON e.id = m.fk_especie
      LEFT JOIN raza
        ON raza.id = m.fk_raza
      INNER JOIN usuario u
        ON u.id = r.fk_usuario
      INNER JOIN ubicacion ub
        ON ub.fk_reporte = r.id
      LEFT JOIN LATERAL (
        SELECT
          (ARRAY_AGG(storage_ref ORDER BY es_principal DESC, id))[1]
            AS foto_storage_ref,
          ARRAY_AGG(storage_ref ORDER BY es_principal DESC, id)
            AS foto_storage_refs
        FROM foto_mascota
        WHERE fk_mascota = m.id
      ) photos ON TRUE
      WHERE (r.estado = 'ACTIVO' AND m.estado = 'PERDIDA')
         OR (r.estado = 'FINALIZADO'
           AND m.estado <> 'INACTIVA'
           AND r.cerrado_en >=
             (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '30 days')
      ORDER BY r.creado_en DESC;
    `);

    /*
      Avistamientos reportados por usuarios.

      Los avistamientos se muestran como tipo "sighting".
      No dependen necesariamente de una mascota registrada, porque pueden ser
      reportes comunitarios de animales vistos en la zona.
    */
    const avistamientosResult = await pool.query(`
      SELECT
        a.id AS avistamiento_id,
        a.descripcion,
        to_char(a.fecha_hora, 'YYYY-MM-DD"T"HH24:MI:SS.MS') || 'Z'
          AS fecha_hora,
        a.fk_reporte_perdida,
        ub.metodo,
        ub.lat,
        ub.lng,
        ub.direccion,
        r.id AS reporte_id,
        m.nombre AS mascota_nombre,
        e.nombre AS especie_nombre,
        raza.nombre AS raza_nombre,
        fa.storage_ref AS foto_storage_ref,
        fa.url_preview AS foto_url_preview
      FROM avistamiento a
      INNER JOIN ubicacion ub
        ON ub.fk_avistamiento = a.id
      LEFT JOIN reporte r ON r.id = a.fk_reporte_perdida
      LEFT JOIN mascota m ON m.id = r.fk_mascota
      LEFT JOIN especie e ON e.id = m.fk_especie
      LEFT JOIN raza ON raza.id = m.fk_raza
      LEFT JOIN LATERAL (
        SELECT storage_ref, url_preview
        FROM foto_avistamiento
        WHERE fk_avistamiento = a.id
        ORDER BY id
        LIMIT 1
      ) fa ON TRUE
      ORDER BY a.fecha_hora DESC;
    `);

    const reportes = reportesResult.rows.map((row) => {
      const isOwner =
        Number.isInteger(req.auth?.userId) &&
        req.auth.userId === Number(row.report_owner_id);
      const isActive = row.reporte_estado === 'ACTIVO';
      const showContact =
        isActive && !isOwner && row.mostrar_contacto === true && Boolean(row.owner_phone);

      return {
        id: `lost_${row.reporte_id}`,
        title: 'Mascota perdida',
        petName: row.mascota_nombre,
        details: [
          row.especie_nombre,
          row.raza_nombre,
          row.mascota_color,
        ]
          .filter(Boolean)
          .join(' · '),
        location: row.metodo === 'DIRECCION' && row.direccion
          ? row.direccion
          : 'Punto marcado en el mapa',
        reference: row.metodo === 'DIRECCION' ? '' : (row.direccion || ''),
        description:
          row.reporte_descripcion || 'Mascota reportada como perdida.',
        dateText: isActive ? row.creado_en : row.cerrado_en,
        createdDateText: row.creado_en,
        closedDateText: row.cerrado_en,
        imageUrl: row.foto_storage_ref
          ? `/api/map/images/${row.foto_storage_ref}`
          : null,
        imageUrls: Array.isArray(row.foto_storage_refs)
          ? row.foto_storage_refs.map((storageRef) =>
            `/api/map/images/${storageRef}`)
          : row.foto_storage_ref
            ? [`/api/map/images/${row.foto_storage_ref}`]
            : [],
        lat: Number(row.lat),
        lng: Number(row.lng),
        type: isActive ? 'lost' : 'found',
        isOwner,
        showContact,
        ownerName: '',
        ownerPhone: showContact ? row.owner_phone : '',
        ownerEmail: '',
      };
    });

    const avistamientos = avistamientosResult.rows.map((row) => {
      const linked =
        row.fk_reporte_perdida !== null &&
        row.fk_reporte_perdida !== undefined;
      return {
        id: `sighting_${row.avistamiento_id}`,
        title: 'Avistamiento',
        petName: linked ? row.mascota_nombre : 'Sin reporte vinculado',
        details: linked
          ? [row.especie_nombre, row.raza_nombre].filter(Boolean).join(' · ')
          : 'Avistamiento independiente',
        location: row.metodo === 'DIRECCION' && row.direccion
          ? row.direccion
          : 'Punto marcado en el mapa',
        reference: '',
        description: row.descripcion,
        dateText: row.fecha_hora,
        imageUrl: row.foto_storage_ref
          ? (row.foto_url_preview || `/api/sightings/images/${row.foto_storage_ref}`)
          : null,
        imageUrls: row.foto_storage_ref
          ? [(row.foto_url_preview || `/api/sightings/images/${row.foto_storage_ref}`)]
          : [],
        lat: Number(row.lat),
        lng: Number(row.lng),
        type: 'sighting',
        isLinked: linked,
        linkedReportId: linked ? Number(row.reporte_id) : null,
        showContact: false,
        isOwner: false,
      };
    });

    const data = [...reportes, ...avistamientos];

    return res.status(200).json({
      ok: true,
      total: data.length,
      data,
    });
  } catch (error) {
    console.error('Error consultando datos del mapa:', error);

    return res.status(500).json({
      ok: false,
      message: 'Error consultando los datos del mapa',
    });
  }
});

module.exports = router;
