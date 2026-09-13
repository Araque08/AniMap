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
       INNER JOIN reporte r
         ON r.fk_mascota = f.fk_mascota AND r.estado = 'ACTIVO'
       INNER JOIN mascota m
         ON m.id = f.fk_mascota AND m.estado = 'PERDIDA'
       WHERE f.storage_ref = $1 AND f.es_principal = TRUE
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
        to_char(r.creado_en, 'YYYY-MM-DD"T"HH24:MI:SS.MS') || '-05:00' AS creado_en,
        CASE WHEN r.cerrado_en IS NULL THEN NULL
          ELSE to_char(r.cerrado_en, 'YYYY-MM-DD"T"HH24:MI:SS.MS') || '-05:00'
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

        ub.lat,
        ub.lng,
        ub.direccion,
        fp.storage_ref AS foto_storage_ref
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
        SELECT storage_ref
        FROM foto_mascota
        WHERE fk_mascota = m.id AND es_principal = TRUE
        LIMIT 1
      ) fp ON TRUE
      WHERE r.estado = 'ACTIVO' AND m.estado = 'PERDIDA'
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
        a.fecha_hora,
        a.estado,
        ub.lat,
        ub.lng,
        ub.direccion,
        u.nombre AS reporter_name
      FROM avistamiento a
      INNER JOIN usuario u
        ON u.id = a.fk_usuario
      INNER JOIN ubicacion ub
        ON ub.fk_avistamiento = a.id
      ORDER BY a.fecha_hora DESC;
    `);

    const reportes = reportesResult.rows.map((row) => {
      const isOwner =
        Number.isInteger(req.auth?.userId) &&
        req.auth.userId === Number(row.report_owner_id);
      const showContact =
        !isOwner && row.mostrar_contacto === true && Boolean(row.owner_phone);

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
        location: row.direccion || 'Ubicación reportada en el mapa',
        description:
          row.reporte_descripcion || 'Mascota reportada como perdida.',
        dateText: row.creado_en,
        imageUrl: row.foto_storage_ref
          ? `/api/map/images/${row.foto_storage_ref}`
          : null,
        lat: Number(row.lat),
        lng: Number(row.lng),
        type: 'lost',
        isOwner,
        showContact,
        ownerName: '',
        ownerPhone: showContact ? row.owner_phone : '',
        ownerEmail: '',
      };
    });

    const avistamientos = avistamientosResult.rows.map((row) => ({
      id: `sighting_${row.avistamiento_id}`,
      title: 'Avistamiento',
      petName: 'No identificado',
      details: 'Avistamiento reportado por la comunidad',
      location: row.direccion || 'Ubicación reportada en el mapa',
      description: row.descripcion || 'Avistamiento reportado en la zona.',
      dateText: row.fecha_hora,
      imageUrl: null,
      lat: Number(row.lat),
      lng: Number(row.lng),
      type: 'sighting',
      showContact: false,
      ownerName: row.reporter_name || 'Usuario de la comunidad',
      ownerPhone: '',
      ownerEmail: '',
    }));

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
