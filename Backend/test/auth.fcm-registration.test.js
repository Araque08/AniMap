const test = require('node:test');
const assert = require('node:assert/strict');
const { createAuthSessionService, authSessionService } = require('../src/modules/auth/auth.session.service');
const { signAccessToken, signRefreshToken } = require('../src/utils/jwt');

function harness() {
  const state = { sessions: [
    { id: 11, user: 7, device: 'installation-a', active: true, expired: false, registration: null },
    { id: 12, user: 8, device: 'installation-b', active: true, expired: false, registration: null },
  ], push: [], fail: false, released: 0 };
  let backup;
  const client = {
    async query(sql, p = []) {
      const s = sql.replace(/\s+/g, ' ').trim();
      if (s === 'BEGIN') { backup = structuredClone(state.sessions); return {}; }
      if (s === 'COMMIT') { backup = null; return {}; }
      if (s === 'ROLLBACK') { state.sessions = backup || state.sessions; return {}; }
      if (s.includes('pg_advisory_xact_lock')) return {};
      if (s.startsWith('INSERT INTO device_push_registration')) {
        let row = state.push.find(x => x.user === p[0] && x.device === p[1]);
        if (!row) { row = { user: p[0], device: p[1] }; state.push.push(row); }
        if (!row.session || row.session <= p[2]) Object.assign(row, { session: p[2], registration: p[3], active: true });
        return { rowCount: 1, rows: [] };
      }
      if (s.startsWith('UPDATE device_push_registration')) {
        for (const row of state.push) {
          const match = s.includes('fk_device_session = $2')
            ? row.user === p[0] && row.session === p[1] && (p[2] == null || row.registration === p[2])
            : row.registration === p[0] && (row.user !== p[1] || row.device !== p[2]);
          if (match) { row.active = false; row.registration = null; }
        }
        return { rowCount: 1, rows: [] };
      }
      if (s.startsWith('SELECT') && s.includes('ds.fk_usuario')) {
        const row = state.sessions.find(x => x.user === p[0] && x.device === p[1]);
        return { rowCount: row ? 1 : 0, rows: row ? [{ id: row.id,
          fk_usuario: row.user, device_id: row.device, refresh_token_hash: row.refreshHash,
          vigente: row.active, session_expired: row.expired }] : [] };
      }
      if (s.includes('SET vigente = FALSE')) {
        const row = state.sessions.find(x => x.id === p[0]);
        if (row) row.active = false;
        return { rowCount: row ? 1 : 0, rows: [] };
      }
      if (s.startsWith('SELECT') && s.includes('fcm_registration_id =')) {
        const newer = state.sessions.some(x => x.id > p[0] &&
          ((x.device === p[1] && (p[3] == null || x.user === p[3])) || x.registration === p[2]));
        return { rowCount: newer ? 1 : 0, rows: [] };
      }
      if (s.startsWith('SELECT') && s.includes('FROM device_session')) {
        const row = state.sessions.find(x => x.id === p[0] && x.user === p[1] &&
          x.device === p[2] && x.active && !x.expired);
        return { rowCount: row ? 1 : 0, rows: row ? [{ id: row.id }] : [] };
      }
      if (s.includes('SET fcm_registration_id = NULL') && s.includes('id <>')) {
        for (const row of state.sessions) if (row.registration === p[0] && row.id !== p[1]) row.registration = null;
        return { rowCount: 1, rows: [] };
      }
      if (s.includes('SET fcm_registration_id = NULL')) {
        const row = state.sessions.find(x => x.id === p[0] && x.user === p[1] &&
          x.device === p[2] && x.registration === p[3]);
        if (row) row.registration = null;
        return { rowCount: row ? 1 : 0, rows: [] };
      }
      if (s.includes('SET fcm_registration_id = $1')) {
        if (state.fail) throw Object.assign(new Error('sensitive-provider-detail'), { code: '42703' });
        const row = state.sessions.find(x => x.id === p[1] && x.user === p[2] &&
          x.device === p[3] && x.active && !x.expired);
        if (row) row.registration = p[0];
        return { rowCount: row ? 1 : 0, rows: [] };
      }
      throw new Error('Unexpected isolated query');
    },
    release() { state.released++; },
  };
  const service = createAuthSessionService({
    pool: { connect: async () => client, query: (...a) => client.query(...a) },
    compareToken: async (plain, stored) => plain === stored,
  });
  const auth = (index = 0) => ({ userId: state.sessions[index].user,
    sessionId: state.sessions[index].id, deviceId: state.sessions[index].device });
  return { service, state, auth };
}

test('FCM se asocia solo a la sesion y propietario autenticados', async () => {
  const { service, state, auth } = harness();
  assert.deepEqual(await service.setFcmRegistration(auth(), 'fixture-fid-a'), { registered: true });
  assert.ok(state.sessions[0].registration);
  assert.equal(state.sessions[1].registration, null);
});

test('registro repetido es idempotente y actualizarlo reemplaza el anterior', async () => {
  const { service, state, auth } = harness();
  await service.setFcmRegistration(auth(), 'fixture-fid-a');
  await service.setFcmRegistration(auth(), 'fixture-fid-a');
  await service.setFcmRegistration(auth(), 'fixture-fid-b');
  assert.equal(state.sessions.filter(x => x.registration).length, 1);
  assert.ok(state.sessions[0].registration.endsWith('-b'));
});

test('cambio de usuario retira el identificador de la sesion anterior', async () => {
  const { service, state, auth } = harness();
  await service.setFcmRegistration(auth(), 'fixture-fid-a');
  await service.setFcmRegistration(auth(1), 'fixture-fid-a');
  assert.equal(state.sessions[0].registration, null);
  assert.ok(state.sessions[1].registration);
  await assert.rejects(service.setFcmRegistration(auth(), 'fixture-fid-a'), { code: 'FCM_SESSION_SUPERSEDED' });
  assert.ok(state.sessions[1].registration);
});

test('una solicitud tardia del mismo dispositivo no recupera la asociacion', async () => {
  const { service, state, auth } = harness();
  state.sessions[1].device = state.sessions[0].device;
  state.sessions[1].user = state.sessions[0].user;
  await assert.rejects(service.setFcmRegistration(auth(), 'fixture-fid-new'), { code: 'FCM_SESSION_SUPERSEDED' });
  assert.equal(state.sessions[0].registration, null);
});

test('otro usuario no puede bloquear mi asociación usando el mismo deviceId con un FID diferente', async () => {
  const { service, state, auth } = harness();
  state.sessions[1].device = state.sessions[0].device;
  await service.setFcmRegistration(auth(1), 'fixture-fid-user-b');
  await service.setFcmRegistration(auth(), 'fixture-fid-user-a');
  assert.equal(state.push.filter(x => x.active).length, 2);
});

for (const condition of ['active', 'expired', 'owner']) {
  test(`sesion invalida (${condition}) no puede asociar FCM`, async () => {
    const { service, state, auth } = harness();
    const identity = auth();
    if (condition === 'active') state.sessions[0].active = false;
    if (condition === 'expired') state.sessions[0].expired = true;
    if (condition === 'owner') identity.userId = 99;
    await assert.rejects(service.setFcmRegistration(identity, 'fixture-fid-a'), { code: 'SESSION_REVOKED' });
    assert.equal(state.sessions[0].registration, null);
  });
}

test('desasociar es idempotente y no elimina el identificador renovado', async () => {
  const { service, state, auth } = harness();
  await service.setFcmRegistration(auth(), 'fixture-fid-b');
  await service.removeFcmRegistration(auth(), 'fixture-fid-a');
  assert.ok(state.sessions[0].registration);
  await service.removeFcmRegistration(auth(1), 'fixture-fid-b');
  assert.ok(state.sessions[0].registration);
  await service.removeFcmRegistration(auth(), 'fixture-fid-b');
  assert.deepEqual(await service.removeFcmRegistration(auth(), 'fixture-fid-b'), { registered: false });
  assert.equal(state.sessions[0].registration, null);
});

test('logout real del servicio vuelve inelegible la asociacion y rechaza volver a asociar', async () => {
  const { service, state, auth } = harness();
  await service.setFcmRegistration(auth(), 'fixture-fid-a');
  const refresh = signRefreshToken({ sub: 7, deviceId: state.sessions[0].device });
  state.sessions[0].refreshHash = refresh;
  assert.deepEqual(await service.logoutSession(refresh), { revoked: true });
  assert.equal(state.sessions[0].active, false);
  assert.equal(state.push[0].active, false);
  await assert.rejects(service.setFcmRegistration(auth(), 'fixture-fid-a'), { code: 'SESSION_REVOKED' });
});

test('inactividad de API conserva push; logout explícito aun con refresh vencido lo retira', async () => {
  const { service, state, auth } = harness();
  await service.setFcmRegistration(auth(), 'fixture-fid-independent');
  state.sessions[0].expired = true;
  assert.equal(state.push[0].active, true);
  const refresh = signRefreshToken({ sub: 7, deviceId: state.sessions[0].device });
  state.sessions[0].refreshHash = refresh;
  await service.logoutSession(refresh);
  assert.equal(state.push[0].active, false);
});

test('logout con prueba de sesión ya inactiva retira push sin cambiar el error HTTP existente', async () => {
  const { service, state, auth } = harness();
  await service.setFcmRegistration(auth(), 'fixture-fid-independent');
  state.sessions[0].active = false;
  const refresh = signRefreshToken({ sub: 7, deviceId: state.sessions[0].device });
  state.sessions[0].refreshHash = refresh;
  await assert.rejects(service.logoutSession(refresh), { code: 'SESSION_REVOKED' });
  assert.equal(state.push[0].active, false);
});

test('fallo SQL revierte la transferencia y oculta detalles sensibles', async () => {
  const { service, state, auth } = harness();
  state.sessions[0].registration = 'fixture-fid-a';
  state.fail = true;
  await assert.rejects(service.setFcmRegistration(auth(1), 'fixture-fid-a'), error =>
    error.code === 'FCM_REGISTRATION_UNAVAILABLE' &&
    !error.message.includes('sensitive-provider-detail') && !error.message.includes('fixture-fid'));
  assert.ok(state.sessions[0].registration);
  assert.equal(state.sessions[1].registration, null);
  assert.equal(state.released, 1);
});

test('rutas FCM exigen JWT y rechazan userId/sessionId sin exponer el registro', async t => {
  const restore = require('../test-support/auth-fixture.cjs').installAuthFixture({ 7: 'USUARIO' });
  let calls = 0;
  t.mock.method(authSessionService, 'setFcmRegistration', async auth => {
    calls++; assert.equal(auth.userId, 7); assert.equal(auth.sessionId, 7);
    return { registered: true };
  });
  t.mock.method(authSessionService, 'removeFcmRegistration', async () => ({ registered: false }));
  const app = require('../src/app');
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const url = `http://127.0.0.1:${server.address().port}/api/auth/fcm-registration`;
  const token = signAccessToken({ sub: 7, deviceId: 'fixture-device' });
  const send = (body, authorized = true, method = 'PUT') => fetch(url, { method,
    headers: { 'Content-Type': 'application/json', ...(authorized ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body) });
  try {
    assert.equal((await send({ registrationId: 'fixture-fid-a' }, false)).status, 401);
    assert.equal((await send({ registrationId: 'fixture-fid-a' }, false, 'DELETE')).status, 401);
    assert.equal((await send({ registrationId: 'fixture-fid-a', userId: 9 }, true, 'DELETE')).status, 400);
    for (const body of [{}, { registrationId: '' }, { registrationId: 'x'.repeat(256) },
      { registrationId: 'fixture-fid-a', userId: 9 }, { registrationId: 'fixture-fid-a', sessionId: 9 }]) {
      const response = await send(body);
      assert.equal(response.status, 400);
      assert.ok(!(await response.text()).includes('fixture-fid-a'));
    }
    const response = await send({ registrationId: 'fixture-fid-a' });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true, data: { registered: true } });
    assert.equal(calls, 1);
    const removed = await send({ registrationId: 'fixture-fid-a' }, true, 'DELETE');
    assert.equal(removed.status, 200);
    assert.deepEqual(await removed.json(), { ok: true, data: { registered: false } });
  } finally {
    restore(); await new Promise(resolve => server.close(resolve));
  }
});
