const express = require('express');
const pool = require('../../config/postgres_db');

const router = express.Router();

/*
  GET /api/map/reports

  Esta ruta entrega al mapa los datos que antes estaban quemados en Flutter.
  Por ahora consulta PostgreSQL y arma una respuesta lista para pintar:
  - Mascotas perdidas: vienen de reporte + mascota + ubicación.
  - Mascotas encontradas: vienen de reporte finalizado + mascota + ubicación.
  - Avistamientos: vienen de avistamiento + ubicación.

  Más adelante se puede ampliar para filtros por radio, especie, raza o fecha.
*/
router.get('/reports', async (req, res) => {
  try {
    /*
      Reportes de mascotas perdidas o encontradas.

      Si el reporte está ACTIVO, el mapa lo interpreta como "lost".
      Si el reporte está FINALIZADO, el mapa lo interpreta como "found".
    */
    const reportesResult = await pool.query(`
      SELECT
        r.id AS reporte_id,
        r.descripcion AS reporte_descripcion,
        r.estado AS reporte_estado,
        r.creado_en,
        r.cerrado_en,
        r.mostrar_contacto,

        m.id AS mascota_id,
        m.nombre AS mascota_nombre,
        m.color AS mascota_color,
        m.sexo AS mascota_sexo,
        m.estado AS mascota_estado,

        e.nombre AS especie_nombre,
        raza.nombre AS raza_nombre,

        u.nombre AS owner_name,
        u.telefono AS owner_phone,
        u.email AS owner_email,

        ub.lat,
        ub.lng,
        ub.direccion
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
      WHERE r.estado IN ('ACTIVO', 'FINALIZADO')
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
      const isFound = row.reporte_estado === 'FINALIZADO';

      return {
        id: `${isFound ? 'found' : 'lost'}_${row.reporte_id}`,
        title: isFound ? 'Mascota encontrada' : 'Mascota perdida',
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
          row.reporte_descripcion ||
          (isFound
            ? 'El reporte fue finalizado porque la mascota fue encontrada.'
            : 'Mascota reportada como perdida.'),
        dateText: isFound
          ? row.cerrado_en || row.creado_en
          : row.creado_en,
        imageUrl: null,
        lat: Number(row.lat),
        lng: Number(row.lng),
        type: isFound ? 'found' : 'lost',
        showContact: row.mostrar_contacto === true,
        ownerName: row.mostrar_contacto ? row.owner_name : '',
        ownerPhone: row.mostrar_contacto ? row.owner_phone : '',
        ownerEmail: row.mostrar_contacto ? row.owner_email : '',
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
