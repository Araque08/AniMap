const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');

const env = require('../src/config/env');
const { signRefreshToken } = require('../src/utils/jwt');
const { hashRefreshToken, compareRefreshToken } = require('../src/utils/hash');
const {
  createAuthSessionService,
} = require('../src/modules/auth/auth.session.service');

function createHarness(overrides = {}) {
  const state = {
    session: {
      id: 41,
      fk_usuario: 7,
      device_id: 'device-a',
      refresh_token_hash: '',
      vigente: true,
      session_expired: false,
      email: 'session-test@example.invalid',
      is_verified: true,
      estado_cuenta: 'ACTIVO',
      ...overrides,
    },
    updatedSessionIds: [],
    roles: ['USUARIO'],
  };

  const client = {
    async query(sql, params = []) {
      const normalized = sql.replace(/\s+/g, ' ').trim();
      if (normalized === 'BEGIN' || normalized === 'COMMIT' || normalized === 'ROLLBACK') {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('SELECT') && normalized.includes('FROM device_session')) {
        const matches =
          params[0] === state.session.fk_usuario &&
          params[1] === state.session.device_id;
        return { rowCount: matches ? 1 : 0, rows: matches ? [{ ...state.session }] : [] };
      }
      if (normalized.includes('FROM usuario_rol')) {
        return { rowCount: state.roles.length, rows: state.roles.map((nombre) => ({ nombre })) };
      }
      if (normalized.includes('SET refresh_token_hash')) {
        state.session.refresh_token_hash = params[0];
        state.session.vigente = true;
        state.updatedSessionIds.push(params[2]);
        return { rowCount: 1, rows: [] };
      }
      if (normalized.includes('SET vigente = FALSE')) {
        state.session.vigente = false;
        state.updatedSessionIds.push(params[0]);
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Consulta inesperada en prueba: ${normalized.slice(0, 80)}`);
    },
    release() {},
  };

  const service = createAuthSessionService({
    pool: { connect: async () => client },
    compareToken: async (plain, stored) => plain === stored,
    hashToken: async (plain) => plain,
    accessSigner: () => 'access-test-token',
  });
  return { service, state };
}

test('refresh válido rota el token y actualiza la misma device_session', async () => {
  const { service, state } = createHarness();
  const tokenA = signRefreshToken({ sub: 7, deviceId: 'device-a', jti: 'a' });
  state.session.refresh_token_hash = tokenA;
  const result = await service.refreshSession(tokenA);
  assert.equal(result.accessToken, 'access-test-token');
  assert.equal(result.role, 'USUARIO');
  assert.notEqual(result.refreshToken, tokenA);
  assert.equal(state.session.refresh_token_hash, result.refreshToken);
  assert.deepEqual(state.updatedSessionIds, [41]);
});

test('hash de refresh distingue JWT largos con prefijo compartido', async () => {
  const commonPrefix = 'x'.repeat(100);
  const tokenA = `${commonPrefix}a`;
  const tokenB = `${commonPrefix}b`;
  const stored = hashRefreshToken(tokenA);
  assert.equal(await compareRefreshToken(tokenA, stored), true);
  assert.equal(await compareRefreshToken(tokenB, stored), false);
});

test('refresh anterior no se puede reutilizar después de la rotación', async () => {
  const { service, state } = createHarness();
  const tokenA = signRefreshToken({ sub: 7, deviceId: 'device-a', jti: 'a' });
  state.session.refresh_token_hash = tokenA;
  const { refreshToken: tokenB } = await service.refreshSession(tokenA);
  await assert.rejects(service.refreshSession(tokenA), { code: 'REFRESH_TOKEN_INVALID' });
  await assert.doesNotReject(service.refreshSession(tokenB));
});

test('refresh consulta el rol vigente y conserva ADMINISTRADOR', async () => {
  const { service, state } = createHarness();
  state.roles = ['ADMINISTRADOR'];
  const token = signRefreshToken({ sub: 7, deviceId: 'device-a', jti: 'admin' });
  state.session.refresh_token_hash = token;
  const result = await service.refreshSession(token);
  assert.equal(result.role, 'ADMINISTRADOR');
});

test('refresh sin rol o con multirrol no rota la sesión', async () => {
  for (const roles of [[], ['USUARIO', 'ADMINISTRADOR']]) {
    const { service, state } = createHarness();
    state.roles = roles;
    const token = signRefreshToken({ sub: 7, deviceId: 'device-a', jti: 'invalid-role' });
    state.session.refresh_token_hash = token;
    await assert.rejects(service.refreshSession(token), { code: 'ACCOUNT_ROLE_INVALID' });
    assert.equal(state.session.refresh_token_hash, token);
  }
});

test('refresh expirado se rechaza con código estable', async () => {
  const { service } = createHarness();
  const expired = jwt.sign(
    { sub: 7, deviceId: 'device-a' },
    env.JWT_REFRESH_SECRET,
    { expiresIn: -1 },
  );
  await assert.rejects(service.refreshSession(expired), { code: 'REFRESH_TOKEN_EXPIRED' });
});

test('device_session revocada rechaza refresh', async () => {
  const { service, state } = createHarness({ vigente: false });
  const token = signRefreshToken({ sub: 7, deviceId: 'device-a', jti: 'revoked' });
  state.session.refresh_token_hash = token;
  await assert.rejects(service.refreshSession(token), { code: 'SESSION_REVOKED' });
});

test('device_session expirada rechaza refresh', async () => {
  const { service, state } = createHarness({ session_expired: true });
  const token = signRefreshToken({ sub: 7, deviceId: 'device-a', jti: 'expired-session' });
  state.session.refresh_token_hash = token;
  await assert.rejects(service.refreshSession(token), { code: 'REFRESH_TOKEN_EXPIRED' });
});

test('cuenta inválida rechaza refresh', async () => {
  const { service, state } = createHarness({ estado_cuenta: 'INACTIVO' });
  const token = signRefreshToken({ sub: 7, deviceId: 'device-a', jti: 'account' });
  state.session.refresh_token_hash = token;
  await assert.rejects(service.refreshSession(token), { code: 'ACCOUNT_INVALID' });
});

test('logout revoca solo la sesión identificada por el refresh token', async () => {
  const { service, state } = createHarness();
  const token = signRefreshToken({ sub: 7, deviceId: 'device-a', jti: 'logout' });
  state.session.refresh_token_hash = token;
  const result = await service.logoutSession(token);
  assert.deepEqual(result, { revoked: true });
  assert.equal(state.session.vigente, false);
  assert.deepEqual(state.updatedSessionIds, [41]);
});

test('logout acepta access vencido porque no depende del access token', async () => {
  const { service, state } = createHarness();
  const token = signRefreshToken({ sub: 7, deviceId: 'device-a', jti: 'logout-no-access' });
  state.session.refresh_token_hash = token;
  await assert.doesNotReject(service.logoutSession(token));
});
