const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { once } = require('node:events');

const app = require('../src/app');
const db = require('../src/config/postgres_db');
const { hashText } = require('../src/utils/hash');

const integrationTest =
  process.env.ANIMAP_RUN_ACCOUNT_SETTINGS_INTEGRATION === '1'
    ? test
    : test.skip;

async function request(baseUrl, path, { method = 'GET', token, body } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return { status: response.status, body: await response.json() };
}

integrationTest(
  'preferencias y sesiones reales respetan propiedad, revocación y limpieza',
  async () => {
    const suffix = randomUUID();
    const password = `Settings-${suffix.slice(0, 8)}-A1!`;
    const passwordHash = await hashText(password);
    const emailA = `settings-a-${suffix}@example.invalid`;
    const emailB = `settings-b-${suffix}@example.invalid`;
    const deviceA1 = `settings-a1-${suffix}`;
    const deviceA2 = `settings-a2-${suffix}`;
    const deviceB = `settings-b-${suffix}`;
    let userA;
    let userB;

    const server = app.listen(0, '127.0.0.1');
    await once(server, 'listening');
    const { port } = server.address();
    const baseUrl = `http://127.0.0.1:${port}`;

    async function login(email, deviceId) {
      const result = await request(baseUrl, '/api/auth/login', {
        method: 'POST',
        body: { email, password, deviceId },
      });
      assert.equal(result.status, 200);
      return result.body.data;
    }

    try {
      const inserted = await db.pool.query(
        `INSERT INTO usuario
           (nombre, email, telefono, password_hash, is_verified, acepta_tyc, estado_cuenta)
         VALUES
           ('Settings A temporal', $1, '3000000001', $3, TRUE, TRUE, 'ACTIVO'),
           ('Settings B temporal', $2, '3000000002', $3, TRUE, TRUE, 'ACTIVO')
         RETURNING id, email`,
        [emailA, emailB, passwordHash]
      );
      userA = inserted.rows.find((row) => row.email === emailA).id;
      userB = inserted.rows.find((row) => row.email === emailB).id;
      await db.pool.query(
        'INSERT INTO perfil (fk_usuario) VALUES ($1), ($2)',
        [userA, userB]
      );

      const sessionA1 = await login(emailA, deviceA1);
      const sessionA2 = await login(emailA, deviceA2);
      const sessionB = await login(emailB, deviceB);

      const anonymousPreferences = await request(
        baseUrl,
        '/api/notification-preferences'
      );
      assert.equal(anonymousPreferences.status, 401);

      const defaults = await request(
        baseUrl,
        '/api/notification-preferences',
        { token: sessionA1.accessToken }
      );
      assert.equal(defaults.status, 200);
      assert.deepEqual(defaults.body.data, {
        notificacionesActivas: true,
        radioKm: 2,
        especieFiltro: null,
        tipoEvento: null,
        soloMiZona: false,
      });
      const absentBeforeSave = await db.pool.query(
        'SELECT 1 FROM preferencia_notificacion WHERE fk_usuario = $1',
        [userA]
      );
      assert.equal(absentBeforeSave.rowCount, 0);

      const saved = await request(
        baseUrl,
        '/api/notification-preferences',
        {
          method: 'PATCH',
          token: sessionA1.accessToken,
          body: {
            notificacionesActivas: false,
            soloMiZona: true,
            especieFiltro: 'Gato',
            tipoEvento: 'ENCONTRADO',
            radioKm: 5,
          },
        }
      );
      assert.equal(saved.status, 200);
      assert.deepEqual(saved.body.data, {
        notificacionesActivas: false,
        radioKm: 5,
        especieFiltro: 'Gato',
        tipoEvento: 'ENCONTRADO',
        soloMiZona: true,
      });

      const reloaded = await request(
        baseUrl,
        '/api/notification-preferences',
        { token: sessionA1.accessToken }
      );
      assert.deepEqual(reloaded.body.data, saved.body.data);
      const persisted = await db.pool.query(
        `SELECT
           p.notificaciones_activas,
           pn.solo_mi_zona,
           pn.especie_filtro,
           pn.tipo_evento,
           pn.radio_km::int
         FROM perfil p
         JOIN preferencia_notificacion pn ON pn.fk_usuario = p.fk_usuario
         WHERE p.fk_usuario = $1`,
        [userA]
      );
      assert.deepEqual(persisted.rows[0], {
        notificaciones_activas: false,
        solo_mi_zona: true,
        especie_filtro: 'Gato',
        tipo_evento: 'ENCONTRADO',
        radio_km: 5,
      });

      const rejectedOwnerOverride = await request(
        baseUrl,
        '/api/notification-preferences',
        {
          method: 'PATCH',
          token: sessionA1.accessToken,
          body: {
            userId: userB,
            notificacionesActivas: false,
            soloMiZona: true,
            especieFiltro: 'Perro',
            tipoEvento: 'PERDIDA',
            radioKm: 1,
          },
        }
      );
      assert.equal(rejectedOwnerOverride.status, 400);
      const profileB = await db.pool.query(
        'SELECT notificaciones_activas FROM perfil WHERE fk_usuario = $1',
        [userB]
      );
      assert.equal(profileB.rows[0].notificaciones_activas, true);

      await db.pool.query(
        `INSERT INTO device_session (
           fk_usuario, device_id, refresh_token_hash, creado_en, expira_en, vigente
         ) VALUES ($1, $2, 'temporal-no-token', NOW() - INTERVAL '2 days',
                   NOW() - INTERVAL '1 day', TRUE)`,
        [userA, `expired-${suffix}`]
      );

      const sessionsA = await request(baseUrl, '/api/auth/sessions', {
        token: sessionA1.accessToken,
      });
      assert.equal(sessionsA.status, 200);
      assert.equal(sessionsA.body.data.length, 2);
      assert.equal(sessionsA.body.data[0].isCurrent, true);
      assert.equal(sessionsA.body.data[1].isCurrent, false);
      assert.equal(JSON.stringify(sessionsA.body).includes('refresh_token'), false);
      assert.equal(JSON.stringify(sessionsA.body).includes('hash'), false);

      const currentRevoke = await request(
        baseUrl,
        `/api/auth/sessions/${sessionsA.body.data[0].id}/revoke`,
        { method: 'POST', token: sessionA1.accessToken }
      );
      assert.equal(currentRevoke.status, 409);

      const sessionsB = await request(baseUrl, '/api/auth/sessions', {
        token: sessionB.accessToken,
      });
      assert.equal(sessionsB.body.data.length, 1);
      const foreignRevoke = await request(
        baseUrl,
        `/api/auth/sessions/${sessionsB.body.data[0].id}/revoke`,
        { method: 'POST', token: sessionA1.accessToken }
      );
      assert.equal(foreignRevoke.status, 404);

      const otherA = sessionsA.body.data.find((item) => !item.isCurrent);
      const revoked = await request(
        baseUrl,
        `/api/auth/sessions/${otherA.id}/revoke`,
        { method: 'POST', token: sessionA1.accessToken }
      );
      assert.equal(revoked.status, 200);
      const revokedRefresh = await request(baseUrl, '/api/auth/refresh', {
        method: 'POST',
        body: { refreshToken: sessionA2.refreshToken },
      });
      assert.equal(revokedRefresh.status, 401);
      assert.equal(revokedRefresh.body.code, 'SESSION_REVOKED');

      const refreshedCurrent = await request(baseUrl, '/api/auth/refresh', {
        method: 'POST',
        body: { refreshToken: sessionA1.refreshToken },
      });
      assert.equal(refreshedCurrent.status, 200);
      const sameSession = await db.pool.query(
        `SELECT COUNT(*)::int AS count
         FROM device_session
         WHERE fk_usuario = $1 AND device_id = $2`,
        [userA, deviceA1]
      );
      assert.equal(sameSession.rows[0].count, 1);
    } finally {
      if (userA && userB) {
        await db.pool.query(
          'DELETE FROM usuario WHERE (id = $1 AND email = $3) OR (id = $2 AND email = $4)',
          [userA, userB, emailA, emailB]
        );
        const residue = await db.pool.query(
          `SELECT
             (SELECT COUNT(*)::int FROM usuario WHERE id IN ($1, $2)) AS usuarios,
             (SELECT COUNT(*)::int FROM perfil WHERE fk_usuario IN ($1, $2)) AS perfiles,
             (SELECT COUNT(*)::int FROM preferencia_notificacion WHERE fk_usuario IN ($1, $2)) AS preferencias,
             (SELECT COUNT(*)::int FROM device_session WHERE fk_usuario IN ($1, $2)) AS sesiones`,
          [userA, userB]
        );
        assert.deepEqual(residue.rows[0], {
          usuarios: 0,
          perfiles: 0,
          preferencias: 0,
          sesiones: 0,
        });
      }
      await new Promise((resolve, reject) => {
        server.close((error) => (error ? reject(error) : resolve()));
      });
    }
  }
);
