const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/postgres_db');
const auth = require('../src/middleware/auth.middleware');
const { signAccessToken } = require('../src/utils/jwt');

async function authorize(t, { exists = true, expired = false, active = true, renewed = true, role = 'USUARIO' } = {}) {
  const calls = [];
  t.mock.method(db, 'query', async (sql) => {
    calls.push(sql);
    if (sql.includes('FROM device_session')) return { rowCount: exists ? 1 : 0, rows: [{
      session_id: 1, session_expired: expired, estado_cuenta: active ? 'ACTIVO' : 'SUSPENDIDO',
      is_verified: true, email: 'fixture@example.invalid' }] };
    if (sql.includes('FROM usuario_rol')) return { rowCount: 1, rows: [{ nombre: role }] };
    return { rowCount: renewed ? 1 : 0, rows: renewed ? [{ id: 1 }] : [] };
  });
  const req = { get: () => `Bearer ${signAccessToken({ sub: 7, deviceId: 'test', role: 'ADMINISTRADOR' })}` };
  const res = { status(code) { this.code = code; return this; }, json(body) { this.body = body; } };
  let next = false;
  await auth(req, res, () => { next = true; });
  return { req, res, next, calls };
}
test('autorización usa rol vigente aunque JWT todavía diga administrador', async t => {
  const result = await authorize(t);
  assert.equal(result.next, true);
  assert.equal(result.req.auth.role, 'USUARIO');
});
for (const [name, options, status] of [
  ['revocada', { exists: false }, 401], ['expirada', { expired: true }, 401],
  ['cuenta suspendida', { active: false }, 403],
  ['revocada entre consulta y renovación', { renewed: false }, 401],
]) test(`sesión ${name} no autoriza`, async t => {
  const { res, next } = await authorize(t, options);
  assert.equal(res.code, status);
  assert.equal(next, false);
});
