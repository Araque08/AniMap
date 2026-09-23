const test = require('node:test');
const assert = require('node:assert/strict');
const { getSingleRole } = require('../src/modules/auth/auth.role.service');
const requireRole = require('../src/middleware/role.middleware');
const { loginUser } = require('../src/modules/auth/auth.service');
const { hashText } = require('../src/utils/hash');
const { verifyAccessToken } = require('../src/utils/jwt');

function roleClient(roles) {
  return { query: async () => ({ rowCount: roles.length, rows: roles.map((nombre) => ({ nombre })) }) };
}

test('rol único USUARIO y ADMINISTRADOR se obtiene desde PostgreSQL', async () => {
  assert.equal(await getSingleRole(roleClient(['USUARIO']), 1), 'USUARIO');
  assert.equal(await getSingleRole(roleClient(['ADMINISTRADOR']), 1), 'ADMINISTRADOR');
});

test('cero roles o multirrol se rechazan expresamente', async () => {
  await assert.rejects(getSingleRole(roleClient([]), 1), { code: 'ACCOUNT_ROLE_INVALID' });
  await assert.rejects(getSingleRole(roleClient(['USUARIO', 'ADMINISTRADOR']), 1), { code: 'ACCOUNT_ROLE_INVALID' });
});

test('RBAC exige autenticación y rol ADMINISTRADOR', () => {
  const middleware = requireRole('ADMINISTRADOR');
  const response = () => ({ status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } });
  const missing = response();
  middleware({}, missing, () => assert.fail('No debe autorizar'));
  assert.equal(missing.statusCode, 401);
  const user = response();
  middleware({ auth: { role: 'USUARIO' } }, user, () => assert.fail('No debe autorizar'));
  assert.equal(user.statusCode, 403);
  let called = false;
  middleware({ auth: { role: 'ADMINISTRADOR' } }, response(), () => { called = true; });
  assert.equal(called, true);
});

test('login firma rol real y conserva deviceId, refresh y usuario', async () => {
  const passwordHash = await hashText('ClavePrueba123*');
  for (const role of ['USUARIO', 'ADMINISTRADOR']) {
    const client = {
      async query(sql) {
        if (sql.includes('FROM usuario_rol')) return { rowCount: 1, rows: [{ nombre: role }] };
        if (sql.includes('FROM usuario') && sql.includes('WHERE email')) {
          return { rowCount: 1, rows: [{ id: 7, nombre: 'Prueba', email: 'prueba@example.invalid',
            password_hash: passwordHash, estado_cuenta: 'ACTIVO', is_verified: true }] };
        }
        if (sql.includes('FROM usuario') && sql.includes('WHERE id')) {
          return { rowCount: 1, rows: [{ id: 7, nombre: 'Prueba' }] };
        }
        return { rowCount: 1, rows: [] };
      },
      release() {},
    };
    const result = await loginUser({ email: 'prueba@example.invalid', password: 'ClavePrueba123*',
      deviceId: 'device-test' }, { pool: { connect: async () => client } });
    const claim = verifyAccessToken(result.accessToken);
    assert.equal(claim.role, role);
    assert.equal(claim.deviceId, 'device-test');
    assert.equal(result.user.rol, role);
    assert.ok(result.refreshToken);
  }
});
