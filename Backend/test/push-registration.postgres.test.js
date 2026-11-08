const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { promisify } = require('node:util');
const execFile = promisify(require('node:child_process').execFile);
const { spawn } = require('node:child_process');
// pg_ctl's descendants can inherit handles on Windows. Wait for pg_ctl's exit,
// not for inherited stdout handles to close after the server has started.
function control(executable, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, { stdio: 'ignore', windowsHide: true });
    child.once('error', reject);
    child.once('exit', code => code === 0 ? resolve() : reject(new Error('Temporary pg_ctl failed')));
  });
}

// Opt-in: creates its OWN temporary cluster, never reads a DB URL or .env.
test('isolated PostgreSQL: migration, idle expiry, transfer, guarded invalidation and revocation',
  { skip: process.env.ANIMAP_RUN_PUSH_PG_TESTS !== '1', timeout: 90000 }, async () => {
    const bin = process.env.ANIMAP_TEST_PG_BIN;
    assert.ok(bin, 'Set ANIMAP_TEST_PG_BIN to the installed PostgreSQL bin directory');
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'animap-push-pg-'));
    const data = path.join(directory, 'data');
    const server = net.createServer();
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    await new Promise(resolve => server.close(resolve));
    let pool, started = false;
    try {
      await execFile(path.join(bin, 'initdb.exe'), ['-D', data, '-U', 'animap_test', '-A', 'trust', '--no-locale', '-E', 'UTF8']);
      await control(path.join(bin, 'pg_ctl.exe'), ['-D', data, '-l', path.join(directory, 'postgres.log'),
        '-o', `-h 127.0.0.1 -p ${port} -F`, '-w', 'start']);
      started = true;
      pool = new (require('pg').Pool)({ host: '127.0.0.1', port, user: 'animap_test',
        database: 'postgres', max: 2, connectionTimeoutMillis: 3000 });
      await pool.query(`CREATE TABLE usuario(id INTEGER PRIMARY KEY, email TEXT, is_verified BOOLEAN,
        estado_cuenta TEXT);
        CREATE TABLE device_session(id INTEGER PRIMARY KEY, fk_usuario INTEGER REFERENCES usuario,
          device_id VARCHAR(120), refresh_token_hash TEXT, vigente BOOLEAN, expira_en TIMESTAMP,
          fcm_registration_id VARCHAR(255) UNIQUE, fcm_registration_updated_at TIMESTAMP);
        CREATE TABLE avistamiento(id INTEGER PRIMARY KEY);
        CREATE TABLE notificacion(id SERIAL PRIMARY KEY, fk_usuario INTEGER REFERENCES usuario,
          fk_reporte INTEGER, titulo TEXT, mensaje TEXT, tipo TEXT, estado_envio TEXT, audiencia TEXT, fecha TIMESTAMP);
        INSERT INTO usuario VALUES (7, 'one@example.invalid', TRUE, 'ACTIVO'),
          (8, 'two@example.invalid', TRUE, 'ACTIVO');
        INSERT INTO device_session VALUES (11, 7, 'fixture-a', '', TRUE, NOW() + INTERVAL '1 hour',
          'fixture-fid-a', NOW()), (12, 8, 'fixture-b', '', TRUE, NOW() + INTERVAL '1 hour', NULL, NULL);`);
      await pool.query(await fs.readFile(path.join(__dirname, '../database/migrations/20261101_sighting_push_notifications.sql'), 'utf8'));
      const sessionsBefore = (await pool.query('SELECT * FROM device_session ORDER BY id')).rows;
      await pool.query(await fs.readFile(path.join(__dirname, '../database/migrations/20261102_independent_push_registration.sql'), 'utf8'));
      assert.deepEqual((await pool.query('SELECT * FROM device_session ORDER BY id')).rows, sessionsBefore);
      const { createAuthSessionService } = require('../src/modules/auth/auth.session.service');
      const { createNotificationsRepository } = require('../src/modules/notifications/notifications.repository');
      const { signRefreshToken } = require('../src/utils/jwt');
      const auth = createAuthSessionService({ pool, compareToken: async (a, b) => a === b });
      const repo = createNotificationsRepository(pool);
      const a = { userId: 7, sessionId: 11, deviceId: 'fixture-a' };
      const b = { userId: 8, sessionId: 12, deviceId: 'fixture-b' };
      assert.equal((await repo.listTargets(7)).length, 1, 'backfill');
      await auth.setFcmRegistration(a, 'fixture-fid-a');
      await pool.query("UPDATE device_session SET expira_en = NOW() - INTERVAL '1 hour' WHERE id = 11");
      assert.equal((await repo.listTargets(7)).length, 1, 'API expiry must not revoke push');
      await auth.setFcmRegistration(b, 'fixture-fid-a');
      assert.equal((await repo.listTargets(7)).length, 0);
      let target = (await repo.listTargets(8))[0];
      const fingerprint = require('node:crypto').createHash('sha256').update(target.registrationId).digest('hex');
      const delivery = { pushRegistrationId: target.pushRegistrationId, fingerprint };
      const original = await repo.currentTarget(delivery, 8);
      assert.ok(original);
      const notification = (await pool.query("INSERT INTO notificacion(fk_usuario,tipo,estado_envio) VALUES (8,'AVISTAMIENTO_VINCULADO','PENDIENTE') RETURNING id")).rows[0].id;
      await repo.planDeliveries(notification, [{ sessionId: target.id,
        pushRegistrationId: target.pushRegistrationId, fingerprint }]);
      await repo.planDeliveries(notification, [{ sessionId: target.id,
        pushRegistrationId: target.pushRegistrationId, fingerprint }]);
      const claimed = (await Promise.all([repo.claimDelivery(notification), repo.claimDelivery(notification)])).filter(Boolean);
      assert.equal(claimed.length, 1, 'atomic claim and unique delivery');
      await repo.finishDelivery(claimed[0], { state: 'ACEPTADA_FCM',
        messageId: 'projects/animapbd/messages/mock', acceptedAt: new Date().toISOString() });
      assert.equal(await repo.claimDelivery(notification), null);
      assert.equal((await pool.query('SELECT recibido_en FROM notificacion_entrega')).rows[0].recibido_en, null);
      await auth.setFcmRegistration(b, 'fixture-fid-new');
      await repo.invalidateTarget(delivery, 8, original);
      assert.equal((await repo.listTargets(8))[0].registrationId, 'fixture-fid-new');
      await auth.removeFcmRegistration(a, 'fixture-fid-new');
      assert.equal((await repo.listTargets(8)).length, 1, 'wrong owner cannot remove');
      const refresh = signRefreshToken({ sub: 8, deviceId: 'fixture-b' });
      await pool.query('UPDATE device_session SET refresh_token_hash = $1 WHERE id = 12', [refresh]);
      await pool.query('UPDATE device_session SET vigente = FALSE WHERE id = 12');
      await assert.rejects(auth.logoutSession(refresh), { code: 'SESSION_REVOKED' });
      assert.equal((await repo.listTargets(8)).length, 0);
      // The revocation CTE must still succeed for a session without push.
      await pool.query("INSERT INTO device_session VALUES (13,7,'fixture-c','',TRUE,NOW()+INTERVAL '1 hour',NULL,NULL)");
      assert.deepEqual(await auth.revokeSession(7, 'fixture-a', 13), { revoked: true });
      assert.equal((await pool.query('SELECT COUNT(*)::int AS n FROM usuario')).rows[0].n, 2);
    } finally {
      await pool?.end();
      if (started) await control(path.join(bin, 'pg_ctl.exe'), ['-D', data, '-m', 'fast', '-w', 'stop']);
      // Only the exact temporary directory created above is removed.
      if (path.dirname(directory) === os.tmpdir() && path.basename(directory).startsWith('animap-push-pg-')) {
        await fs.rm(directory, { recursive: true, force: true });
      }
    }
  });
