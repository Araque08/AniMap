// Called only inside the existing authentication transaction/advisory lock.
async function registerPush(client, { userId, sessionId, deviceId }, registrationId) {
  await client.query(
    `UPDATE device_push_registration SET activo = FALSE, fcm_registration_id = NULL,
       revocado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC',
       actualizado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
     WHERE fcm_registration_id = $1
       AND (fk_usuario <> $2 OR device_id <> $3)`, [registrationId, userId, deviceId]);
  await client.query(
    `INSERT INTO device_push_registration
       (fk_usuario, device_id, fk_device_session, fcm_registration_id)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (fk_usuario, device_id) DO UPDATE
       SET fk_device_session = EXCLUDED.fk_device_session,
         fcm_registration_id = EXCLUDED.fcm_registration_id, activo = TRUE,
         revocado_en = NULL, actualizado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
       WHERE device_push_registration.fk_device_session IS NULL
         OR device_push_registration.fk_device_session <= EXCLUDED.fk_device_session`,
    [userId, deviceId, sessionId, registrationId]);
}

async function revokePush(queryable, userId, sessionId, registrationId = null) {
  await queryable.query(
    `UPDATE device_push_registration SET activo = FALSE, fcm_registration_id = NULL,
       revocado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC',
       actualizado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
     WHERE fk_usuario = $1 AND fk_device_session = $2
       AND ($3::text IS NULL OR fcm_registration_id = $3)`,
    [userId, sessionId, registrationId]);
}

async function revokeOwnerPush(queryable, userId) {
  await queryable.query(
    `UPDATE device_push_registration SET activo = FALSE, fcm_registration_id = NULL,
       revocado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC',
       actualizado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
     WHERE fk_usuario = $1`, [userId]);
}

module.exports = { registerPush, revokePush, revokeOwnerPush };
