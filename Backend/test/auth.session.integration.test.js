const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { once } = require('node:events');

const db = require('../src/config/postgres_db');
const app = require('../src/app');
const { hashText } = require('../src/utils/hash');

const integrationTest =
  process.env.ANIMAP_RUN_SESSION_INTEGRATION === '1' ? test : test.skip;

async function api(baseUrl, path, body) {
  const response = await fetch(`${baseUrl}/api/auth${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

integrationTest(
  'sesión real rota refresh, revoca un dispositivo y deja cero residuos',
  async () => {
    const suffix = randomUUID();
    const email = `session-e2e-${suffix}@example.invalid`;
    const password = `Session-${suffix.slice(0, 8)}-A1!`;
    const passwordHash = await hashText(password);
    let userId;
    const server = app.listen(0, '127.0.0.1');
    await once(server, 'listening');
    const address = server.address();
    const baseUrl = `http://127.0.0.1:${address.port}`;

    try {
      const inserted = await db.pool.query(
        `INSERT INTO usuario
           (nombre, email, telefono, password_hash, is_verified, acepta_tyc, estado_cuenta)
         VALUES ($1, $2, $3, $4, TRUE, TRUE, 'ACTIVO')
         RETURNING id`,
        ['Session E2E temporal', email, '3000000000', passwordHash],
      );
      userId = inserted.rows[0].id;

      const loginA = await api(baseUrl, '/login', {
        email,
        password,
        deviceId: `device-a-${suffix}`,
      });
      assert.equal(loginA.status, 200);
      const tokenA = loginA.body.data.refreshToken;

      const loginB = await api(baseUrl, '/login', {
        email,
        password,
        deviceId: `device-b-${suffix}`,
      });
      assert.equal(loginB.status, 200);
      const tokenDeviceB = loginB.body.data.refreshToken;

      const firstRotation = await api(baseUrl, '/refresh', { refreshToken: tokenA });
      assert.equal(firstRotation.status, 200);
      const tokenB = firstRotation.body.data.refreshToken;
      assert.notEqual(tokenB, tokenA);

      const reusedA = await api(baseUrl, '/refresh', { refreshToken: tokenA });
      assert.equal(reusedA.status, 401);
      assert.equal(reusedA.body.code, 'REFRESH_TOKEN_INVALID');

      const secondRotation = await api(baseUrl, '/refresh', { refreshToken: tokenB });
      assert.equal(secondRotation.status, 200);
      const currentDeviceAToken = secondRotation.body.data.refreshToken;

      const logoutA = await api(baseUrl, '/logout', {
        refreshToken: currentDeviceAToken,
      });
      assert.equal(logoutA.status, 200);

      const rejectedAfterLogout = await api(baseUrl, '/refresh', {
        refreshToken: currentDeviceAToken,
      });
      assert.equal(rejectedAfterLogout.status, 401);
      assert.equal(rejectedAfterLogout.body.code, 'SESSION_REVOKED');

      const deviceBStillWorks = await api(baseUrl, '/refresh', {
        refreshToken: tokenDeviceB,
      });
      assert.equal(deviceBStillWorks.status, 200);

      const sessions = await db.pool.query(
        `SELECT device_id, vigente
         FROM device_session
         WHERE fk_usuario = $1
         ORDER BY device_id`,
        [userId],
      );
      assert.equal(sessions.rowCount, 2);
      assert.equal(sessions.rows.filter((row) => row.vigente).length, 1);
    } finally {
      if (userId) {
        const deleted = await db.pool.query(
          'DELETE FROM usuario WHERE id = $1 AND email = $2 RETURNING id',
          [userId, email],
        );
        assert.equal(deleted.rowCount, 1);
        const residue = await db.pool.query(
          `SELECT
             (SELECT COUNT(*)::int FROM usuario WHERE id = $1) AS usuario,
             (SELECT COUNT(*)::int FROM device_session WHERE fk_usuario = $1) AS sesiones`,
          [userId],
        );
        assert.deepEqual(residue.rows[0], { usuario: 0, sesiones: 0 });
      }
      await new Promise((resolve, reject) => {
        server.close((error) => (error ? reject(error) : resolve()));
      });
    }
  },
);
