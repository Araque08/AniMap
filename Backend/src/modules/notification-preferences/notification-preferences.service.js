
const db = require('../../config/postgres_db');

// =====================================================
// PREFERENCIAS PREDETERMINADAS
// =====================================================

const DEFAULTS = Object.freeze({
  radioKm: 2,
  especieFiltro: null,
  tipoEvento: null,
  soloMiZona: false,
  barrioNotificaciones: null,

  // HU-064
  latReferencia: null,
  lngReferencia: null,
});

function createHttpError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

// =====================================================
// CONVERTIR DATOS DE POSTGRESQL A RESPUESTA JSON
// =====================================================

function mapPreferences(row) {
  return {
    notificacionesActivas: row.notificaciones_activas,
    radioKm: Number(row.radio_km ?? DEFAULTS.radioKm),
    especieFiltro: row.especie_filtro ?? DEFAULTS.especieFiltro,
    tipoEvento: row.tipo_evento ?? DEFAULTS.tipoEvento,
    soloMiZona: row.solo_mi_zona ?? DEFAULTS.soloMiZona,

    // HU-049: Barrio asociado a las notificaciones.
    barrioNotificaciones:
      row.barrio_notificaciones ?? DEFAULTS.barrioNotificaciones,
        // HU-064: Ubicación de referencia.
    latReferencia:
      row.lat_referencia == null
        ? null
        : Number(row.lat_referencia),

    lngReferencia:
      row.lng_referencia == null
        ? null
        : Number(row.lng_referencia),
  };
}

// =====================================================
// SERVICIO DE PREFERENCIAS
// =====================================================

function createNotificationPreferencesService({
  pool = db.pool,
} = {}) {

  // ===================================================
  // CONSULTAR PREFERENCIAS DEL USUARIO
  // ===================================================

  async function queryPreferences(queryable, userId) {
    const result = await queryable.query(
      `
      SELECT
        p.notificaciones_activas,
        p.barrio_notificaciones,
        pn.radio_km,
        pn.especie_filtro,
        pn.tipo_evento,
        pn.solo_mi_zona,
        pn.lat_referencia,
        pn.lng_referencia
      FROM perfil p
      LEFT JOIN preferencia_notificacion pn
        ON pn.fk_usuario = p.fk_usuario
      WHERE p.fk_usuario = $1
      LIMIT 1
      `,
      [userId]
    );

    if (result.rowCount === 0) {
      throw createHttpError('Perfil no encontrado', 404);
    }

    return mapPreferences(result.rows[0]);
  }

  async function getPreferences(userId) {
    return queryPreferences(pool, userId);
  }

  // ===================================================
  // GUARDAR PREFERENCIAS DEL USUARIO
  // ===================================================

  async function updatePreferences(userId, data) {
    const client = await pool.connect();
      // HU-064: Detectar si el cliente envió
      // una nueva ubicación de referencia.
      const actualizarUbicacion =
        Object.hasOwn(data, 'latReferencia') &&
        Object.hasOwn(data, 'lngReferencia');

    try {
      await client.query('BEGIN');

      // =================================================
      // ACTUALIZAR PERFIL
      // =================================================

      // Si una versión antigua de Flutter no envía
      // barrioNotificaciones, conservamos el barrio actual.
      //
      // Si lo envía como null, permitimos borrar el barrio.

      const actualizarBarrio =
        Object.prototype.hasOwnProperty.call(
          data,
          'barrioNotificaciones'
        );

      const profile = await client.query(
        `
        UPDATE perfil
        SET
          notificaciones_activas = $2,

          barrio_notificaciones = CASE
            WHEN $3::boolean
              THEN $4::varchar(100)
            ELSE barrio_notificaciones
          END

        WHERE fk_usuario = $1

        RETURNING fk_usuario
        `,
        [
          userId,
          data.notificacionesActivas,
          actualizarBarrio,
          data.barrioNotificaciones ?? null,
        ]
      );

      if (profile.rowCount === 0) {
        throw createHttpError('Perfil no encontrado', 404);
      }

      // =================================================
      // ACTUALIZAR LAS OTRAS PREFERENCIAS
      // =================================================


      await client.query(
        `
        INSERT INTO preferencia_notificacion (
          fk_usuario,
          radio_km,
          especie_filtro,
          tipo_evento,
          solo_mi_zona,
          lat_referencia,
          lng_referencia
        )
        VALUES ($1, $2, $3, $4, $5, $7, $8)

        ON CONFLICT (fk_usuario)
        DO UPDATE SET
          radio_km = EXCLUDED.radio_km,
          especie_filtro = EXCLUDED.especie_filtro,
          tipo_evento = EXCLUDED.tipo_evento,
          solo_mi_zona = EXCLUDED.solo_mi_zona,

          lat_referencia = CASE
            WHEN $6::boolean
              THEN EXCLUDED.lat_referencia
            ELSE preferencia_notificacion.lat_referencia
          END,

          lng_referencia = CASE
            WHEN $6::boolean
              THEN EXCLUDED.lng_referencia
            ELSE preferencia_notificacion.lng_referencia
          END
        `,
        [
          userId,
          data.radioKm,
          data.especieFiltro,
          data.tipoEvento,
          data.soloMiZona,
          actualizarUbicacion,
          data.latReferencia ?? null,
          data.lngReferencia ?? null,
        ]
      );


      // Consultar las preferencias actualizadas.
      const preferences = await queryPreferences(
        client,
        userId
      );

      await client.query('COMMIT');

      return preferences;

    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;

    } finally {
      client.release();
    }
  }

  return {
    getPreferences,
    updatePreferences,
  };
}

module.exports = {
  DEFAULTS,
  createNotificationPreferencesService,
  notificationPreferencesService:
    createNotificationPreferencesService(),
};
