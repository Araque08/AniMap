const test = require('node:test');
const assert = require('node:assert/strict');

test('registry transfer is scoped by authenticated session and old revocations cannot clear a new login', async () => {
  const { registerPush, revokePush } = require('../src/modules/auth/push-registration.repository');
  const calls = [];
  const client = { query: async (sql, params) => { calls.push({ sql, params }); return { rows: [] }; } };
  await registerPush(client, { userId: 7, sessionId: 11, deviceId: 'fixture-device' }, 'fixture-registration');
  assert.match(calls[0].sql, /fcm_registration_id = \$1|device_id = \$2/);
  assert.match(calls[1].sql, /ON CONFLICT \(fk_usuario, device_id\) DO UPDATE/);
  assert.match(calls[1].sql, /fk_device_session <= EXCLUDED.fk_device_session/);
  assert.deepEqual(calls[1].params, [7, 'fixture-device', 11, 'fixture-registration']);
  await revokePush(client, 7, 11, 'fixture-old');
  const revoke = calls.at(-1);
  assert.match(revoke.sql, /fk_usuario = \$1 AND fk_device_session = \$2/);
  assert.match(revoke.sql, /fcm_registration_id = \$3/);
  assert.deepEqual(revoke.params, [7, 11, 'fixture-old']);
});
