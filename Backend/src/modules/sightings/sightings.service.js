const postgres = require('../../config/postgres_db');
const defaultImages = require('./sightings.images.repository');
const geofence = require('../geofence/geofence.service');

function createHttpError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

const SIGHTING_SELECT = `
  SELECT
    a.id, a.descripcion, a.fk_reporte_perdida,
    to_char(a.fecha_hora, 'YYYY-MM-DD"T"HH24:MI:SS.MS') || 'Z' AS fecha_hora,
    ub.metodo, ub.lat, ub.lng, ub.precision_m, ub.direccion, ub.place_id,
    fa.storage_ref, fa.url_preview,
    r.id AS reporte_id,
    m.nombre AS mascota_nombre,
    e.nombre AS especie_nombre,
    raza.nombre AS raza_nombre
  FROM avistamiento a
  INNER JOIN ubicacion ub ON ub.fk_avistamiento = a.id
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
  ) fa ON TRUE`;

function normalizeSighting(row) {
  const linked = row.fk_reporte_perdida !== null && row.fk_reporte_perdida !== undefined;
  return {
    id: Number(row.id),
    descripcion: row.descripcion,
    fechaHora: row.fecha_hora,
    ubicacion: {
      metodo: row.metodo,
      lat: Number(row.lat),
      lng: Number(row.lng),
      precisionM: row.precision_m === null ? null : Number(row.precision_m),
      direccion: row.direccion,
      placeId: row.place_id,
    },
    foto: row.storage_ref
      ? {
          id: row.storage_ref,
          url: row.url_preview || `/api/sightings/images/${row.storage_ref}`,
        }
      : null,
    vinculado: linked,
    reporte: linked
      ? {
          id: Number(row.reporte_id),
          mascota: {
            nombre: row.mascota_nombre,
            especie: row.especie_nombre,
            raza: row.raza_nombre,
          },
        }
      : null,
  };
}

function createSightingsService(
  pool = postgres.pool,
  images = defaultImages,
  allowedArea = geofence
) {
  async function querySighting(queryable, sightingId) {
    const result = await queryable.query(
      `${SIGHTING_SELECT} WHERE a.id = $1`,
      [sightingId]
    );
    if (result.rowCount === 0) {
      throw createHttpError('Avistamiento no encontrado', 404);
    }
    return normalizeSighting(result.rows[0]);
  }

  async function listLinkableReports() {
    const result = await pool.query(`
      SELECT
        r.id,
        m.nombre,
        e.nombre AS especie,
        raza.nombre AS raza,
        fp.storage_ref,
        fp.url_preview
      FROM reporte r
      INNER JOIN mascota m ON m.id = r.fk_mascota
      INNER JOIN especie e ON e.id = m.fk_especie
      LEFT JOIN raza ON raza.id = m.fk_raza
      LEFT JOIN LATERAL (
        SELECT storage_ref, url_preview
        FROM foto_mascota
        WHERE fk_mascota = m.id AND es_principal = TRUE
        ORDER BY id
        LIMIT 1
      ) fp ON TRUE
      WHERE r.estado = 'ACTIVO' AND m.estado = 'PERDIDA'
      ORDER BY r.creado_en DESC, r.id DESC
    `);
    return result.rows.map((row) => ({
      id: Number(row.id),
      mascota: {
        nombre: row.nombre,
        especie: row.especie,
        raza: row.raza,
        fotoPrincipal: row.storage_ref
          ? {
              id: row.storage_ref,
              url: `/api/map/images/${row.storage_ref}`,
            }
          : null,
      },
    }));
  }

  async function getPublicSighting(sightingId) {
    return querySighting(pool, sightingId);
  }

  async function getReportHistory(userId, reportId, period = 'ALL') {
    const periodCondition = {
      ALL: '',
      TODAY: `AND a.fecha_hora >= (
        date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE 'America/Bogota')
        AT TIME ZONE 'America/Bogota' AT TIME ZONE 'UTC'
      )`,
      '7D': `AND a.fecha_hora >=
        (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '7 days'`,
      '30D': `AND a.fecha_hora >=
        (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '30 days'`,
    }[period];

    if (periodCondition === undefined) {
      throw createHttpError('Período de historial inválido', 400);
    }

    const result = await pool.query(
      `SELECT
        r.id AS reporte_id, r.estado AS reporte_estado,
        m.id AS mascota_id, m.nombre AS mascota_nombre,
        e.nombre AS especie_nombre, raza.nombre AS raza_nombre,
        ur.metodo AS perdida_metodo, ur.lat AS perdida_lat,
        ur.lng AS perdida_lng, ur.precision_m AS perdida_precision_m,
        ur.direccion AS perdida_direccion, ur.place_id AS perdida_place_id,
        fp.storage_ref AS mascota_foto_storage_ref,
        fp.url_preview AS mascota_foto_url_preview,
        (SELECT COUNT(*)::int
         FROM avistamiento total_a
         WHERE total_a.fk_reporte_perdida = r.id) AS total_avistamientos,
        a.id AS avistamiento_id, a.descripcion AS avistamiento_descripcion,
        to_char(a.fecha_hora, 'YYYY-MM-DD"T"HH24:MI:SS.MS') || 'Z'
          AS avistamiento_fecha_hora,
        ua.metodo AS avistamiento_metodo, ua.lat AS avistamiento_lat,
        ua.lng AS avistamiento_lng,
        ua.precision_m AS avistamiento_precision_m,
        ua.direccion AS avistamiento_direccion,
        ua.place_id AS avistamiento_place_id,
        fa.storage_ref AS avistamiento_foto_storage_ref,
        fa.url_preview AS avistamiento_foto_url_preview
       FROM reporte r
       INNER JOIN mascota m ON m.id = r.fk_mascota
       INNER JOIN especie e ON e.id = m.fk_especie
       LEFT JOIN raza ON raza.id = m.fk_raza
       INNER JOIN ubicacion ur ON ur.fk_reporte = r.id
       LEFT JOIN LATERAL (
         SELECT storage_ref, url_preview
         FROM foto_mascota
         WHERE fk_mascota = m.id AND es_principal = TRUE
         ORDER BY id
         LIMIT 1
       ) fp ON TRUE
       LEFT JOIN avistamiento a
         ON a.fk_reporte_perdida = r.id ${periodCondition}
       LEFT JOIN ubicacion ua ON ua.fk_avistamiento = a.id
       LEFT JOIN LATERAL (
         SELECT storage_ref, url_preview
         FROM foto_avistamiento
         WHERE fk_avistamiento = a.id
         ORDER BY id
         LIMIT 1
       ) fa ON TRUE
       WHERE r.id = $1 AND r.fk_usuario = $2
       ORDER BY a.fecha_hora DESC NULLS LAST, a.id DESC NULLS LAST`,
      [reportId, userId]
    );

    if (result.rowCount === 0) {
      throw createHttpError('Reporte no encontrado', 404);
    }

    const context = result.rows[0];
    const sightings = result.rows
      .filter((row) => row.avistamiento_id !== null)
      .map((row) => ({
        id: Number(row.avistamiento_id),
        descripcion: row.avistamiento_descripcion,
        fechaHora: row.avistamiento_fecha_hora,
        ubicacion: {
          metodo: row.avistamiento_metodo,
          lat: Number(row.avistamiento_lat),
          lng: Number(row.avistamiento_lng),
          precisionM: row.avistamiento_precision_m === null
            ? null
            : Number(row.avistamiento_precision_m),
          direccion: row.avistamiento_direccion,
          placeId: row.avistamiento_place_id,
        },
        foto: row.avistamiento_foto_storage_ref
          ? {
              id: row.avistamiento_foto_storage_ref,
              url: row.avistamiento_foto_url_preview ||
                `/api/sightings/images/${row.avistamiento_foto_storage_ref}`,
            }
          : null,
      }));

    return {
      report: {
        id: Number(context.reporte_id),
        estado: context.reporte_estado,
        mascota: {
          id: Number(context.mascota_id),
          nombre: context.mascota_nombre,
          especie: context.especie_nombre,
          raza: context.raza_nombre,
        },
        fotoPrincipal: context.mascota_foto_storage_ref
          ? {
              id: context.mascota_foto_storage_ref,
              url: context.mascota_foto_url_preview ||
                `/api/pets/images/${context.mascota_foto_storage_ref}`,
            }
          : null,
        ubicacionPerdida: {
          metodo: context.perdida_metodo,
          lat: Number(context.perdida_lat),
          lng: Number(context.perdida_lng),
          precisionM: context.perdida_precision_m === null
            ? null
            : Number(context.perdida_precision_m),
          direccion: context.perdida_direccion,
          placeId: context.perdida_place_id,
        },
      },
      period,
      total: Number(context.total_avistamientos || 0),
      filteredTotal: sightings.length,
      sightings,
    };
  }

  async function getPublicImage(imageId) {
    const reference = await pool.query(
      `SELECT 1 FROM foto_avistamiento WHERE storage_ref = $1 LIMIT 1`,
      [imageId]
    );
    if (reference.rowCount === 0) {
      throw createHttpError('Foto de avistamiento no encontrada', 404);
    }
    const image = await images.findPublicSightingImage(imageId);
    const content = image?.imagen || image?.buffer;
    const buffer = Buffer.isBuffer(content)
      ? content
      : content?.buffer
        ? Buffer.from(content.buffer)
        : null;
    if (!buffer) throw createHttpError('Foto de avistamiento no encontrada', 404);
    return { buffer, mimeType: image.mimeType || 'application/octet-stream' };
  }

  async function createSighting(userId, data, file) {
    allowedArea.validateAllowedArea(data.lat, data.lng);
    const client = await pool.connect();
    let mongoImage = null;
    try {
      await client.query('BEGIN');

      if (data.reportId !== null) {
        const reportResult = await client.query(
          `SELECT r.id, r.estado, m.estado AS mascota_estado
           FROM reporte r
           INNER JOIN mascota m ON m.id = r.fk_mascota
           WHERE r.id = $1
           FOR SHARE`,
          [data.reportId]
        );
        if (reportResult.rowCount === 0) {
          throw createHttpError('El reporte seleccionado no existe', 404);
        }
        if (
          reportResult.rows[0].estado !== 'ACTIVO' ||
          reportResult.rows[0].mascota_estado !== 'PERDIDA'
        ) {
          throw createHttpError(
            'El reporte seleccionado ya no está activo',
            409
          );
        }
      }

      const sightingResult = await client.query(
        `INSERT INTO avistamiento (
          fk_usuario, fk_reporte_perdida, descripcion, fecha_hora, estado
        ) VALUES ($1, $2, $3, CURRENT_TIMESTAMP AT TIME ZONE 'UTC', NULL)
        RETURNING id`,
        [userId, data.reportId, data.descripcion]
      );
      const sightingId = sightingResult.rows[0].id;

      await client.query(
        `INSERT INTO ubicacion (
          fk_avistamiento, metodo, lat, lng, precision_m, direccion, place_id,
          "timestamp"
        ) VALUES ($1, $2, $3, $4, $5, $6, $7,
          CURRENT_TIMESTAMP AT TIME ZONE 'UTC')`,
        [
          sightingId,
          data.metodo,
          data.lat,
          data.lng,
          data.precisionM,
          data.direccion,
          data.placeId,
        ]
      );

      if (file) {
        mongoImage = await images.saveSightingImage({ sightingId, userId, file });
        await client.query(
          `INSERT INTO foto_avistamiento (
            fk_avistamiento, storage_ref, url_preview, fecha
          ) VALUES ($1, $2, $3, CURRENT_TIMESTAMP AT TIME ZONE 'UTC')`,
          [sightingId, mongoImage.storageRef, mongoImage.urlPreview]
        );
      }

      const sighting = await querySighting(client, sightingId);
      await client.query('COMMIT');
      // RF-0016: una futura notificación de un avistamiento vinculado debe
      // despacharse desde este punto, únicamente después del COMMIT exitoso.
      return sighting;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if (mongoImage) {
        await images.deleteSightingImage(mongoImage.storageRef).catch(() => undefined);
      }
      throw error;
    } finally {
      client.release();
    }
  }

  return {
    createSighting,
    getPublicImage,
    getPublicSighting,
    getReportHistory,
    listLinkableReports,
  };
}

module.exports = {
  createSightingsService,
  sightingsService: createSightingsService(),
};
