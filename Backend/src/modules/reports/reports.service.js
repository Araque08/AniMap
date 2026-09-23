const postgres = require('../../config/postgres_db');
const geofence = require('../geofence/geofence.service');

function createHttpError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function normalizePet(row) {
  return {
    id: row.id,
    nombre: row.nombre,
    especie: row.especie,
    raza: row.raza,
    estado: row.estado,
    tieneReporteActivo: row.tiene_reporte_activo,
    fotoPrincipal: row.foto_storage_ref
      ? {
          id: row.foto_storage_ref,
          url: row.foto_url_preview || `/api/pets/images/${row.foto_storage_ref}`,
        }
      : null,
  };
}

function normalizeReport(row) {
  return {
    id: row.id,
    mascotaId: row.fk_mascota,
    descripcion: row.descripcion,
    mostrarContacto: row.mostrar_contacto,
    estado: row.estado,
    creadoEn: row.creado_en,
    actualizadoEn: row.actualizado_en,
    cerradoEn: row.cerrado_en,
    avistamientosCount: Number(row.avistamientos_count || 0),
    mascota: {
      id: row.fk_mascota,
      nombre: row.mascota_nombre,
      especie: row.especie_nombre,
      raza: row.raza_nombre,
      estado: row.mascota_estado,
      fotoPrincipal: row.foto_storage_ref
        ? {
            id: row.foto_storage_ref,
            url:
              row.foto_url_preview ||
              `/api/pets/images/${row.foto_storage_ref}`,
          }
        : null,
    },
    ubicacion: {
      metodo: row.ubicacion_metodo,
      lat: Number(row.lat),
      lng: Number(row.lng),
      precisionM:
        row.precision_m === null ? null : Number(row.precision_m),
      referencia: row.ubicacion_metodo === 'DIRECCION' ? null : row.direccion,
      direccion: row.direccion,
      placeId: row.place_id,
    },
  };
}

const REPORT_SELECT = `
  SELECT
    r.id, r.fk_mascota, r.descripcion, r.mostrar_contacto, r.estado,
    to_char((r.creado_en AT TIME ZONE 'UTC') AT TIME ZONE 'America/Bogota',
      'YYYY-MM-DD"T"HH24:MI:SS.MS') || '-05:00' AS creado_en,
    to_char((r.actualizado_en AT TIME ZONE 'UTC') AT TIME ZONE 'America/Bogota',
      'YYYY-MM-DD"T"HH24:MI:SS.MS') || '-05:00' AS actualizado_en,
    CASE WHEN r.cerrado_en IS NULL THEN NULL
      ELSE to_char((r.cerrado_en AT TIME ZONE 'UTC') AT TIME ZONE 'America/Bogota',
        'YYYY-MM-DD"T"HH24:MI:SS.MS') || '-05:00'
    END AS cerrado_en,
    m.nombre AS mascota_nombre, m.estado AS mascota_estado,
    e.nombre AS especie_nombre, raza.nombre AS raza_nombre,
    ub.metodo AS ubicacion_metodo, ub.lat, ub.lng, ub.precision_m,
    ub.direccion, ub.place_id,
    fp.storage_ref AS foto_storage_ref, fp.url_preview AS foto_url_preview,
    (SELECT COUNT(*)::int FROM avistamiento av
     WHERE av.fk_reporte_perdida = r.id) AS avistamientos_count
  FROM reporte r
  INNER JOIN mascota m ON m.id = r.fk_mascota
  INNER JOIN especie e ON e.id = m.fk_especie
  LEFT JOIN raza ON raza.id = m.fk_raza
  INNER JOIN ubicacion ub ON ub.fk_reporte = r.id
  LEFT JOIN LATERAL (
    SELECT storage_ref, url_preview
    FROM foto_mascota
    WHERE fk_mascota = m.id AND es_principal = TRUE
    LIMIT 1
  ) fp ON TRUE`;

function createReportsService(pool = postgres.pool, allowedArea = geofence) {
  async function listReportablePets(userId) {
    const result = await pool.query(
      `SELECT
        m.id, m.nombre, m.estado, e.nombre AS especie, r.nombre AS raza,
        EXISTS (
          SELECT 1 FROM reporte rp
          WHERE rp.fk_mascota = m.id AND rp.estado = 'ACTIVO'
        ) AS tiene_reporte_activo,
        fp.storage_ref AS foto_storage_ref,
        fp.url_preview AS foto_url_preview
      FROM mascota m
      INNER JOIN especie e ON e.id = m.fk_especie
      LEFT JOIN raza r ON r.id = m.fk_raza
      LEFT JOIN LATERAL (
        SELECT storage_ref, url_preview
        FROM foto_mascota
        WHERE fk_mascota = m.id AND es_principal = TRUE
        LIMIT 1
      ) fp ON TRUE
      WHERE m.fk_usuario = $1 AND m.estado <> 'INACTIVA'
      ORDER BY m.nombre, m.id`,
      [userId]
    );

    return result.rows.map(normalizePet);
  }

  async function listOwnReports(userId) {
    const result = await pool.query(
      `${REPORT_SELECT}
       WHERE r.fk_usuario = $1
       ORDER BY r.creado_en DESC, r.id DESC`,
      [userId]
    );
    return result.rows.map(normalizeReport);
  }

  async function getOwnReport(userId, reportId) {
    const result = await pool.query(
      `${REPORT_SELECT}
       WHERE r.id = $1 AND r.fk_usuario = $2`,
      [reportId, userId]
    );
    if (result.rowCount === 0) {
      throw createHttpError('Reporte no encontrado', 404);
    }
    return normalizeReport(result.rows[0]);
  }

  async function createReport(userId, data) {
    allowedArea.validateAllowedArea(data.ubicacion.lat, data.ubicacion.lng);
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const petResult = await client.query(
        `SELECT id, estado
         FROM mascota
         WHERE id = $1 AND fk_usuario = $2 AND estado <> 'INACTIVA'
         FOR UPDATE`,
        [data.mascotaId, userId]
      );
      if (petResult.rowCount === 0) {
        throw createHttpError('Mascota no encontrada o no disponible', 404);
      }

      const activeResult = await client.query(
        `SELECT id FROM reporte
         WHERE fk_mascota = $1 AND estado = 'ACTIVO'`,
        [data.mascotaId]
      );
      if (activeResult.rowCount > 0) {
        throw createHttpError('La mascota ya tiene un reporte activo', 409);
      }

      const reportResult = await client.query(
        `INSERT INTO reporte (
          fk_usuario, fk_mascota, mostrar_contacto, descripcion, estado, creado_en
        ) VALUES ($1, $2, $3, $4, 'ACTIVO', CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
        RETURNING id, estado,
          to_char((creado_en AT TIME ZONE 'UTC') AT TIME ZONE 'America/Bogota',
            'YYYY-MM-DD"T"HH24:MI:SS.MS') || '-05:00' AS creado_en`,
        [
          userId,
          data.mascotaId,
          data.mostrarContacto,
          data.descripcion || null,
        ]
      );
      const report = reportResult.rows[0];

      await client.query(
        `INSERT INTO ubicacion (
          fk_reporte, metodo, lat, lng, precision_m, direccion, place_id, "timestamp"
        ) VALUES ($1, $2, $3, $4, $5, $6, $7,
          CURRENT_TIMESTAMP AT TIME ZONE 'UTC')`,
        [
          report.id,
          data.ubicacion.metodo,
          data.ubicacion.lat,
          data.ubicacion.lng,
          data.ubicacion.precisionM ?? null,
          data.ubicacion.direccion || null,
          data.ubicacion.placeId || null,
        ]
      );

      await client.query(
        `UPDATE mascota
         SET estado = 'PERDIDA', actualizado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
         WHERE id = $1 AND fk_usuario = $2`,
        [data.mascotaId, userId]
      );

      await client.query('COMMIT');
      return report;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if (error.code === '23505') {
        throw createHttpError('La mascota ya tiene un reporte activo', 409);
      }
      throw error;
    } finally {
      client.release();
    }
  }

  async function updateReport(userId, reportId, data) {
    if (data.ubicacion) {
      allowedArea.validateAllowedArea(data.ubicacion.lat, data.ubicacion.lng);
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const currentResult = await client.query(
        `SELECT id, descripcion, mostrar_contacto, estado
         FROM reporte
         WHERE id = $1 AND fk_usuario = $2
         FOR UPDATE`,
        [reportId, userId]
      );
      if (currentResult.rowCount === 0) {
        throw createHttpError('Reporte no encontrado', 404);
      }
      const current = currentResult.rows[0];
      if (current.estado !== 'ACTIVO') {
        throw createHttpError('Un reporte finalizado no puede editarse', 409);
      }

      const descripcion = Object.hasOwn(data, 'descripcion')
        ? data.descripcion || null
        : current.descripcion;
      const mostrarContacto = Object.hasOwn(data, 'mostrarContacto')
        ? data.mostrarContacto
        : current.mostrar_contacto;

      const updateResult = await client.query(
        `UPDATE reporte
         SET descripcion = $1, mostrar_contacto = $2,
             actualizado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
         WHERE id = $3 AND fk_usuario = $4
         RETURNING to_char((actualizado_en AT TIME ZONE 'UTC') AT TIME ZONE 'America/Bogota',
           'YYYY-MM-DD"T"HH24:MI:SS.MS') || '-05:00' AS actualizado_en`,
        [descripcion, mostrarContacto, reportId, userId]
      );

      if (data.ubicacion) {
        const locationResult = await client.query(
          `UPDATE ubicacion
           SET metodo = $1, lat = $2, lng = $3, precision_m = $4,
               direccion = $5, place_id = $6,
               "timestamp" = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
           WHERE fk_reporte = $7`,
          [
            data.ubicacion.metodo,
            data.ubicacion.lat,
            data.ubicacion.lng,
            data.ubicacion.precisionM ?? null,
            data.ubicacion.direccion || null,
            data.ubicacion.placeId || null,
            reportId,
          ]
        );
        if (locationResult.rowCount !== 1) {
          throw createHttpError('La ubicación del reporte no existe', 409);
        }
      }

      await client.query('COMMIT');
      return {
        id: reportId,
        estado: 'ACTIVO',
        actualizadoEn: updateResult.rows[0]?.actualizado_en,
      };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async function closeReport(userId, reportId) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const reportResult = await client.query(
        `SELECT id, fk_mascota, estado
         FROM reporte
         WHERE id = $1 AND fk_usuario = $2
         FOR UPDATE`,
        [reportId, userId]
      );
      if (reportResult.rowCount === 0) {
        throw createHttpError('Reporte no encontrado', 404);
      }
      const report = reportResult.rows[0];
      if (report.estado !== 'ACTIVO') {
        throw createHttpError('El reporte ya está finalizado', 409);
      }

      const closeResult = await client.query(
        `UPDATE reporte
         SET estado = 'FINALIZADO',
             cerrado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC',
             actualizado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
         WHERE id = $1 AND fk_usuario = $2
         RETURNING to_char((cerrado_en AT TIME ZONE 'UTC') AT TIME ZONE 'America/Bogota',
           'YYYY-MM-DD"T"HH24:MI:SS.MS') || '-05:00' AS cerrado_en`,
        [reportId, userId]
      );
      const petResult = await client.query(
        `UPDATE mascota
         SET estado = 'ACTIVA', actualizado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
         WHERE id = $1 AND fk_usuario = $2
         RETURNING id`,
        [report.fk_mascota, userId]
      );
      if (petResult.rowCount !== 1) {
        throw createHttpError('No fue posible actualizar la mascota', 409);
      }

      await client.query('COMMIT');
      return {
        id: reportId,
        estado: 'FINALIZADO',
        cerradoEn: closeResult.rows[0]?.cerrado_en,
      };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if (error.code === '23514' && error.constraint === 'chk_reporte_fechas') {
        throw createHttpError(
          'No fue posible finalizar el reporte por una inconsistencia en sus fechas',
          409
        );
      }
      throw error;
    } finally {
      client.release();
    }
  }

  return {
    closeReport,
    createReport,
    getOwnReport,
    listOwnReports,
    listReportablePets,
    updateReport,
  };
}

module.exports = {
  createReportsService,
  reportsService: createReportsService(),
};
