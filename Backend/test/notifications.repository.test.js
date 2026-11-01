const test = require('node:test');
const assert = require('node:assert/strict');
const { createNotificationsRepository } = require('../src/modules/notifications/notifications.repository');

function setup(rows = []) {
  const calls = [];
  const pool = { async query(sql, params) { calls.push({ sql, params }); return { rows, rowCount: rows.length }; } };
  return { repo: createNotificationsRepository(pool), calls, pool };
}

test('modo QA: consultas de cola y ambas ramas de recuperacion exigen usuario y reporte', async () => {
  const h = setup(); const scope = { ownerId: 28, reportId: 8 };
  await h.repo.recoverAbandoned(scope); await h.repo.pendingNotifications(25, scope);
  await h.repo.claimDelivery(9, scope);
  const recovery = h.calls[0], pending = h.calls[1];
  assert.deepEqual(recovery.params, [28, 8]);
  const branches = recovery.sql.split('UNION');
  assert.equal(branches.length, 2);
  for (const sql of branches) {
    assert.match(sql, /n.fk_usuario = \$1/); assert.match(sql, /n.fk_reporte = \$2/);
  }
  assert.deepEqual(pending.params, [25, 28, 8]);
  assert.match(pending.sql, /n.fk_usuario = \$2/); assert.match(pending.sql, /n.fk_reporte = \$3/);
  assert.match(pending.sql, /n.fk_reporte AS "reportId"/);
  assert.deepEqual(h.calls[2].params, [9, 28, 8]);
  assert.match(h.calls[2].sql, /n.fk_usuario = \$2 AND n.fk_reporte = \$3/);
});

test('dispositivos: SQL limita dueño, sesiones vigentes/no vencidas y cuentas disponibles', async () => {
  const h = setup(); await h.repo.listTargets(28);
  const { sql, params } = h.calls[0];
  assert.deepEqual(params, [28]);
  assert.match(sql, /ds.fk_usuario = \$1/); assert.match(sql, /ds.vigente = TRUE/);
  assert.match(sql, /ds.expira_en > LOCALTIMESTAMP/);
  assert.match(sql, /fcm_registration_id IS NOT NULL/);
  assert.match(sql, /btrim\(ds.fcm_registration_id\) <> ''/);
  assert.match(sql, /u.estado_cuenta = 'ACTIVO'/); assert.match(sql, /u.is_verified = TRUE/);
});

test('origen del destinatario y preferencias sale de las relaciones del avistamiento', async () => {
  const h = setup(); await h.repo.loadEvent(h.pool, 41);
  const { sql, params } = h.calls[0];
  assert.deepEqual(params, [41]);
  assert.match(sql, /r.fk_usuario AS "ownerId"/);
  assert.match(sql, /r.id = a.fk_reporte_perdida/);
  assert.match(sql, /pn.fk_usuario = u.id/);
  assert.match(sql, /ur.fk_reporte = r.id/);
  assert.match(sql, /ua.fk_avistamiento = a.id/);
  assert.doesNotMatch(sql, /email|telefono|password|device_id/);
});

test('intención usa el cliente de la transacción y unicidad por evento/destinatario', async () => {
  const h = setup(); const transactionCalls = [];
  const client = { async query(sql, params) {
    transactionCalls.push({ sql, params }); return { rows: [{ id: 9 }] };
  } };
  assert.equal(await h.repo.insertIntent(client, { ownerId: 28, reportId: 8, sightingId: 41 }, null), 9);
  assert.equal(h.calls.length, 0);
  assert.deepEqual(transactionCalls[0].params.slice(0, 3), [28, 8, 41]);
  assert.match(transactionCalls[0].sql, /ON CONFLICT \(fk_avistamiento, fk_usuario\)/);
  assert.match(transactionCalls[0].sql, /DO NOTHING/);
});

test('plan de entregas persiste huellas e IDs, nunca FID completo; no revive aceptadas', async () => {
  const h = setup(); const assignments = [{ sessionId: 215, fingerprint: 'a'.repeat(64) }];
  await h.repo.planDeliveries(9, assignments);
  assert.deepEqual(JSON.parse(h.calls[0].params[1]), assignments);
  assert.match(h.calls[0].sql, /ON CONFLICT \(fk_notificacion, registro_huella\)/);
  assert.match(h.calls[0].sql, /WHERE notificacion_entrega.estado IN \('PENDIENTE', 'REINTENTO'\)/);
});

test('claim atómico no toma aceptadas, respeta plazo e intentos y permite varios procesos', async () => {
  const h = setup(); await h.repo.claimDelivery(9);
  const { sql, params } = h.calls[0];
  assert.deepEqual(params, [9, null, null]); assert.match(sql, /FOR UPDATE SKIP LOCKED/);
  assert.match(sql, /intentos < 3/);
  assert.match(sql, /proximo_intento_en <= CURRENT_TIMESTAMP AT TIME ZONE 'UTC'/);
  assert.match(sql, /estado IN \('PENDIENTE', 'REINTENTO'\)/);
  assert.match(sql, /intentos = d.intentos \+ 1/);
});

test('antes del envío revalida sesión exacta, propietario, huella, cuenta y expiración', async () => {
  const h = setup(); await h.repo.currentTarget({ sessionId: 215, fingerprint: 'a'.repeat(64) }, 28);
  const { sql, params } = h.calls[0];
  assert.deepEqual(params, [215, 28, 'a'.repeat(64)]);
  assert.match(sql, /ds.id = \$1 AND ds.fk_usuario = \$2 AND ds.vigente = TRUE/);
  assert.match(sql, /ds.expira_en > LOCALTIMESTAMP/);
  assert.match(sql, /sha256\(convert_to\(ds.fcm_registration_id, 'UTF8'\)\)/);
  assert.match(sql, /u.is_verified = TRUE/);
});

test('invalidación condiciona ID, dueño, FID original y versión con precisión completa', async () => {
  const h = setup(); await h.repo.invalidateTarget({ sessionId: 215 }, 28,
    { registrationId: 'fixture-fid-old', updatedAt: '2026-11-01T12:00:00.123456' });
  const { sql, params } = h.calls[0];
  assert.deepEqual(params, [215, 28, 'fixture-fid-old', '2026-11-01T12:00:00.123456']);
  assert.match(sql, /fcm_registration_id = \$3/);
  assert.match(sql, /fcm_registration_updated_at IS NOT DISTINCT FROM \$4::timestamp/);
});

test('aceptación se registra sin confirmar recepción y no sobrescribe otro intento', async () => {
  const h = setup(); await h.repo.finishDelivery({ id: 3, attempts: 2 },
    { state: 'ACEPTADA_FCM', messageId: 'projects/animapbd/messages/mock', acceptedAt: '2026-11-01T12:00:00Z' });
  const { sql, params } = h.calls[0];
  assert.equal(params[2], 'ACEPTADA_FCM'); assert.match(sql, /aceptado_en = \$7/);
  assert.match(sql, /intentos = \$2 AND estado = 'EN_PROCESO'/);
  assert.doesNotMatch(sql, /recibido_en/);
});

test('operaciones interrumpidas pasan a indeterminadas y no se reinician a ciegas', async () => {
  const h = setup([{ fk_notificacion: 9 }]);
  assert.deepEqual(await h.repo.recoverAbandoned(), [9]);
  assert.match(h.calls[0].sql, /estado = 'INDETERMINADA'/);
  assert.match(h.calls[0].sql, /INTERVAL '15 minutes'/);
  assert.match(h.calls[0].sql, /proximo_intento_en = NULL/);
});

test('recuperación también reconcilia un padre pendiente cuyos hijos ya terminaron', async () => {
  const h = setup([{ fk_notificacion: 9 }]); await h.repo.recoverAbandoned();
  const { sql } = h.calls[0];
  assert.match(sql, /UNION/);
  assert.match(sql, /FROM notificacion n/);
  assert.match(sql, /NOT EXISTS[\s\S]*'PENDIENTE', 'REINTENTO', 'EN_PROCESO'/);
});

test('SQL recupera hijos vencidos de plazo aunque el estado agregado sea terminal', async () => {
  const h = setup(); await h.repo.pendingNotifications();
  const { sql } = h.calls[0];
  // Parent status may be stale after a crash or concurrent summary. It must
  // guard only creation of first deliveries, never the due-child OR branch.
  assert.match(sql, /AND \(\(n.estado_envio IN/);
  assert.doesNotMatch(sql, /AND n.estado_envio IN/);
  assert.match(sql, /OR EXISTS[\s\S]*d.estado IN \('PENDIENTE', 'REINTENTO'\)/);
});
