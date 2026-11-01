const postgres = require('../../config/postgres_db');

function createNotificationsRepository(pool = postgres.pool) {
  async function loadEvent(queryable, sightingId) {
    const result = await queryable.query(
      `SELECT a.id AS "sightingId", a.fk_usuario AS "authorId",
         a.fk_reporte_perdida AS "reportId", r.fk_usuario AS "ownerId",
         r.estado AS "reportState", m.estado AS "petState", e.nombre AS species,
         u.estado_cuenta = 'ACTIVO' AS "ownerActive", u.is_verified AS "ownerVerified",
         COALESCE(p.notificaciones_activas, FALSE) AS "notificationsEnabled",
         pn.especie_filtro AS "speciesFilter", pn.tipo_evento AS "eventFilter",
         COALESCE(pn.solo_mi_zona, FALSE) AS "onlyMyZone",
         COALESCE(pn.radio_km, 2) AS "radiusKm",
         ur.lat AS "lostLat", ur.lng AS "lostLng", ua.lat, ua.lng
       FROM avistamiento a
       LEFT JOIN reporte r ON r.id = a.fk_reporte_perdida
       LEFT JOIN mascota m ON m.id = r.fk_mascota
       LEFT JOIN especie e ON e.id = m.fk_especie
       LEFT JOIN usuario u ON u.id = r.fk_usuario
       LEFT JOIN perfil p ON p.fk_usuario = u.id
       LEFT JOIN preferencia_notificacion pn ON pn.fk_usuario = u.id
       LEFT JOIN ubicacion ur ON ur.fk_reporte = r.id
       LEFT JOIN ubicacion ua ON ua.fk_avistamiento = a.id
       WHERE a.id = $1`, [sightingId]
    );
    return result.rows[0] || null;
  }

  async function insertIntent(client, event, reason) {
    const result = await client.query(
      `INSERT INTO notificacion (
         fk_usuario, fk_reporte, fk_avistamiento, titulo, mensaje,
         tipo, estado_envio, audiencia, fecha
       ) VALUES ($1, $2, $3, $4, $5, 'AVISTAMIENTO_VINCULADO', $6,
         'PROPIETARIO', CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
       ON CONFLICT (fk_avistamiento, fk_usuario)
         WHERE fk_avistamiento IS NOT NULL DO NOTHING
       RETURNING id`,
      [event.ownerId, event.reportId, event.sightingId,
        'Nuevo avistamiento de tu mascota',
        'Registraron un avistamiento vinculado a tu reporte de pérdida.',
        reason ? `OMITIDA_${reason}` : 'PENDIENTE']
    );
    return result.rows[0]?.id ?? null;
  }

  async function recoverAbandoned(scope = null) {
    const result = await pool.query(
      `WITH abandoned AS (
         UPDATE notificacion_entrega d
         SET estado = 'INDETERMINADA', ultimo_error = 'PROCESS_INTERRUPTED',
           proximo_intento_en = NULL
         WHERE estado = 'EN_PROCESO'
           AND iniciado_en < (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '15 minutes'
           AND EXISTS (SELECT 1 FROM notificacion n WHERE n.id = d.fk_notificacion
             AND (($1::integer IS NULL AND $2::integer IS NULL)
               OR (n.fk_usuario = $1 AND n.fk_reporte = $2)))
         RETURNING fk_notificacion
       ) SELECT fk_notificacion FROM abandoned
       UNION
       SELECT n.id AS fk_notificacion FROM notificacion n
       WHERE n.tipo = 'AVISTAMIENTO_VINCULADO' AND n.estado_envio IN ('PENDIENTE', 'PARCIAL')
         AND (($1::integer IS NULL AND $2::integer IS NULL)
           OR (n.fk_usuario = $1 AND n.fk_reporte = $2))
         AND EXISTS (SELECT 1 FROM notificacion_entrega d WHERE d.fk_notificacion = n.id)
         AND NOT EXISTS (SELECT 1 FROM notificacion_entrega d
           WHERE d.fk_notificacion = n.id AND d.estado IN ('PENDIENTE', 'REINTENTO', 'EN_PROCESO'))`,
      [scope?.ownerId ?? null, scope?.reportId ?? null]
    );
    return [...new Set(result.rows.map(row => row.fk_notificacion))];
  }

  async function pendingNotifications(limit = 25, scope = null) {
    const result = await pool.query(
      `SELECT n.id, n.fk_avistamiento AS "sightingId", n.fk_usuario AS "ownerId", n.fk_reporte AS "reportId"
       FROM notificacion n
       WHERE n.tipo = 'AVISTAMIENTO_VINCULADO'
         AND (($2::integer IS NULL AND $3::integer IS NULL)
           OR (n.fk_usuario = $2 AND n.fk_reporte = $3))
         AND ((n.estado_envio IN ('PENDIENTE', 'PARCIAL')
           AND NOT EXISTS (SELECT 1 FROM notificacion_entrega d WHERE d.fk_notificacion = n.id))
           OR EXISTS (SELECT 1 FROM notificacion_entrega d
             WHERE d.fk_notificacion = n.id AND d.estado IN ('PENDIENTE', 'REINTENTO')
               AND d.intentos < 3
               AND d.proximo_intento_en <= CURRENT_TIMESTAMP AT TIME ZONE 'UTC'))
       ORDER BY n.id LIMIT $1`, [limit, scope?.ownerId ?? null, scope?.reportId ?? null]
    );
    return result.rows;
  }

  async function listTargets(ownerId) {
    const result = await pool.query(
      `SELECT ds.id, ds.fcm_registration_id AS "registrationId"
       FROM device_session ds INNER JOIN usuario u ON u.id = ds.fk_usuario
       WHERE ds.fk_usuario = $1 AND ds.vigente = TRUE
         AND ds.expira_en > LOCALTIMESTAMP
         AND ds.fcm_registration_id IS NOT NULL AND btrim(ds.fcm_registration_id) <> ''
         AND u.estado_cuenta = 'ACTIVO' AND u.is_verified = TRUE
       ORDER BY ds.id DESC`, [ownerId]
    );
    return result.rows;
  }

  async function planDeliveries(notificationId, assignments) {
    if (!assignments.length) return;
    await pool.query(
      `INSERT INTO notificacion_entrega (fk_notificacion, fk_device_session, registro_huella)
       SELECT $1, x."sessionId", x.fingerprint
       FROM jsonb_to_recordset($2::jsonb) AS x("sessionId" INTEGER, fingerprint TEXT)
       ON CONFLICT (fk_notificacion, registro_huella) DO UPDATE
         SET fk_device_session = EXCLUDED.fk_device_session
         WHERE notificacion_entrega.estado IN ('PENDIENTE', 'REINTENTO')`,
      [notificationId, JSON.stringify(assignments)]
    );
  }

  async function claimDelivery(notificationId, scope = null) {
    const result = await pool.query(
      `WITH candidate AS (
         SELECT id FROM notificacion_entrega
         WHERE fk_notificacion = $1 AND estado IN ('PENDIENTE', 'REINTENTO')
           AND intentos < 3 AND proximo_intento_en <= CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
           AND EXISTS (SELECT 1 FROM notificacion n WHERE n.id = fk_notificacion
             AND (($2::integer IS NULL AND $3::integer IS NULL)
               OR (n.fk_usuario = $2 AND n.fk_reporte = $3)))
         ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1
       ) UPDATE notificacion_entrega d
         SET estado = 'EN_PROCESO', intentos = d.intentos + 1,
           iniciado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
         FROM candidate c WHERE d.id = c.id
         RETURNING d.id, d.fk_device_session AS "sessionId",
           d.registro_huella AS fingerprint, d.intentos AS attempts`,
      [notificationId, scope?.ownerId ?? null, scope?.reportId ?? null]
    );
    return result.rows[0] || null;
  }

  async function currentTarget(delivery, ownerId) {
    const result = await pool.query(
      `SELECT ds.id, ds.fcm_registration_id AS "registrationId",
         to_char(ds.fcm_registration_updated_at, 'YYYY-MM-DD"T"HH24:MI:SS.US') AS "updatedAt"
       FROM device_session ds INNER JOIN usuario u ON u.id = ds.fk_usuario
       WHERE ds.id = $1 AND ds.fk_usuario = $2 AND ds.vigente = TRUE
         AND ds.expira_en > LOCALTIMESTAMP AND ds.fcm_registration_id IS NOT NULL
         AND encode(sha256(convert_to(ds.fcm_registration_id, 'UTF8')), 'hex') = $3
         AND u.estado_cuenta = 'ACTIVO' AND u.is_verified = TRUE`,
      [delivery.sessionId, ownerId, delivery.fingerprint]
    );
    return result.rows[0] || null;
  }

  async function invalidateTarget(delivery, ownerId, original) {
    await pool.query(
      `UPDATE device_session SET fcm_registration_id = NULL,
         fcm_registration_updated_at = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
       WHERE id = $1 AND fk_usuario = $2 AND fcm_registration_id = $3
         AND fcm_registration_updated_at IS NOT DISTINCT FROM $4::timestamp`,
      [delivery.sessionId, ownerId, original.registrationId, original.updatedAt]
    );
  }

  async function finishDelivery(delivery, result) {
    await pool.query(
      `UPDATE notificacion_entrega SET estado = $3, ultimo_error = $4,
         proximo_intento_en = $5, fcm_message_id = $6, aceptado_en = $7
       WHERE id = $1 AND intentos = $2 AND estado = 'EN_PROCESO'`,
      [delivery.id, delivery.attempts, result.state, result.error || null,
        result.nextAt || null, result.messageId || null, result.acceptedAt || null]
    );
  }

  async function skipNotification(id, reason) {
    await pool.query(
      `UPDATE notificacion_entrega SET estado = 'OMITIDA',
         ultimo_error = $2, proximo_intento_en = NULL
       WHERE fk_notificacion = $1 AND estado IN ('PENDIENTE', 'REINTENTO')`, [id, reason]
    );
    await pool.query('UPDATE notificacion SET estado_envio = $2 WHERE id = $1', [id, reason]);
  }

  async function summarize(id) {
    await pool.query(
      `UPDATE notificacion SET estado_envio = (
         SELECT CASE
           WHEN COUNT(*) FILTER (WHERE estado IN ('PENDIENTE', 'REINTENTO', 'EN_PROCESO')) > 0
             THEN CASE WHEN COUNT(*) FILTER (WHERE estado = 'ACEPTADA_FCM') > 0
               THEN 'PARCIAL' ELSE 'PENDIENTE' END
           WHEN COUNT(*) FILTER (WHERE estado = 'INDETERMINADA') > 0 THEN 'INDETERMINADA'
           WHEN COUNT(*) FILTER (WHERE estado = 'ACEPTADA_FCM') = COUNT(*) AND COUNT(*) > 0
             THEN 'ACEPTADA_FCM'
           WHEN COUNT(*) FILTER (WHERE estado = 'ACEPTADA_FCM') > 0 THEN 'PARCIAL_FINAL'
           WHEN COUNT(*) FILTER (WHERE estado = 'FALLIDA_PERMANENTE') > 0 THEN 'FALLIDA_PERMANENTE'
           ELSE 'OMITIDA' END
         FROM notificacion_entrega WHERE fk_notificacion = $1
       ) WHERE id = $1`, [id]
    );
  }

  return { pool, loadEvent, insertIntent, recoverAbandoned, pendingNotifications,
    listTargets, planDeliveries, claimDelivery, currentTarget, invalidateTarget,
    finishDelivery, skipNotification, summarize };
}

module.exports = { createNotificationsRepository };
