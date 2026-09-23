const db = require('../../config/postgres_db');

const DEFAULTS = Object.freeze({
  radioKm: 2,
  especieFiltro: null,
  tipoEvento: null,
  soloMiZona: false,
});

function createHttpError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function mapPreferences(row) {
  return {
    notificacionesActivas: row.notificaciones_activas,
    radioKm: Number(row.radio_km ?? DEFAULTS.radioKm),
    especieFiltro: row.especie_filtro ?? DEFAULTS.especieFiltro,
    tipoEvento: row.tipo_evento ?? DEFAULTS.tipoEvento,
    soloMiZona: row.solo_mi_zona ?? DEFAULTS.soloMiZona,
  };
}

function createNotificationPreferencesService({ pool = db.pool } = {}) {
  async function queryPreferences(queryable, userId) {
    const result = await queryable.query(
      `SELECT
         p.notificaciones_activas,
         pn.radio_km,
         pn.especie_filtro,
         pn.tipo_evento,
         pn.solo_mi_zona
       FROM perfil p
       LEFT JOIN preferencia_notificacion pn ON pn.fk_usuario = p.fk_usuario
       WHERE p.fk_usuario = $1
       LIMIT 1`,
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

  async function updatePreferences(userId, data) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const profile = await client.query(
        `UPDATE perfil
         SET notificaciones_activas = $2
         WHERE fk_usuario = $1
         RETURNING fk_usuario`,
        [userId, data.notificacionesActivas]
      );
      if (profile.rowCount === 0) {
        throw createHttpError('Perfil no encontrado', 404);
      }

      await client.query(
        `INSERT INTO preferencia_notificacion (
           fk_usuario, radio_km, especie_filtro, tipo_evento, solo_mi_zona
         ) VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (fk_usuario) DO UPDATE SET
           radio_km = EXCLUDED.radio_km,
           especie_filtro = EXCLUDED.especie_filtro,
           tipo_evento = EXCLUDED.tipo_evento,
           solo_mi_zona = EXCLUDED.solo_mi_zona`,
        [
          userId,
          data.radioKm,
          data.especieFiltro,
          data.tipoEvento,
          data.soloMiZona,
        ]
      );

      const preferences = await queryPreferences(client, userId);
      await client.query('COMMIT');
      return preferences;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  return { getPreferences, updatePreferences };
}

module.exports = {
  DEFAULTS,
  createNotificationPreferencesService,
  notificationPreferencesService: createNotificationPreferencesService(),
};
