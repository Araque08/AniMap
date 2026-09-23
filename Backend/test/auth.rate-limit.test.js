const test = require('node:test');
const assert = require('node:assert/strict');
const { signAccessToken } = require('../src/utils/jwt');
const authController = require('../src/modules/auth/auth.controller');

// Aislamos los controladores antes de montar las rutas: no se consulta Cloud SQL.
authController.login = (req, res) => res.status(req.validatedBody.password === 'correcta' ? 200 : 401)
  .json(req.validatedBody.password === 'correcta'
    ? { ok: true }
    : { ok: false, message: 'Credenciales inválidas' });
authController.refresh = (_req, res) => res.status(200).json({ ok: true });
authController.logout = (_req, res) => res.status(200).json({ ok: true });
authController.listSessions = (_req, res) => res.status(200).json({ ok: true, data: [] });

const app = require('../src/app');

test('solo POST /api/auth/login acumula fallos y los flujos de sesión no comparten el contador', async () => {
  const server = app.listen(0, '127.0.0.1');
  try {
    await new Promise((resolve) => server.once('listening', resolve));
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const post = (path, body) => fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const login = (password = 'incorrecta') => post('/api/auth/login', {
      email: 'test@example.invalid', password,
    });

    // Al retirar el limiter global, estas rutas conservan protección separada.
    for (const path of ['/api/auth/register', '/api/auth/resend-verification-code', '/api/auth/forgot-password']) {
      for (let attempt = 0; attempt < 10; attempt += 1) {
        assert.equal((await post(path, {})).status, 400);
      }
      const limited = await post(path, {});
      assert.equal(limited.status, 429);
      assert.equal((await limited.json()).message, 'Demasiados intentos. Intenta más tarde.');
    }

    for (let attempt = 0; attempt < 3; attempt += 1) {
      const response = await login();
      assert.equal(response.status, 401);
      assert.equal((await response.json()).message, 'Credenciales inválidas');
      assert.ok(response.headers.get('ratelimit'));
    }

    const accessToken = signAccessToken({ sub: 7, role: 'USUARIO', deviceId: 'test-device' });
    for (let attempt = 0; attempt < 12; attempt += 1) {
      const refresh = await post('/api/auth/refresh', { refreshToken: 'test-refresh' });
      const logout = await post('/api/auth/logout', { refreshToken: 'test-refresh' });
      const sessions = await fetch(`${baseUrl}/api/auth/sessions`, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      const health = await fetch(`${baseUrl}/api/health`);
      assert.deepEqual([refresh.status, logout.status, sessions.status, health.status], [200, 200, 200, 200]);
      assert.equal(refresh.headers.get('ratelimit'), null);
      assert.equal(logout.headers.get('ratelimit'), null);
      assert.equal(sessions.headers.get('ratelimit'), null);
    }

    assert.equal((await login('correcta')).status, 200);
    for (let attempt = 0; attempt < 7; attempt += 1) {
      assert.equal((await login()).status, 401);
    }
    const blocked = await login();
    assert.equal(blocked.status, 429);
    assert.equal((await blocked.json()).message,
      'Demasiados intentos de inicio de sesión. Intenta nuevamente en unos minutos.');

    // Ni el bloqueo de login impide usar otras rutas ni las convierte en 429.
    assert.equal((await post('/api/auth/refresh', { refreshToken: 'test-refresh' })).status, 200);
    assert.equal((await post('/api/auth/logout', { refreshToken: 'test-refresh' })).status, 200);
    assert.equal((await fetch(`${baseUrl}/api/auth/sessions`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    })).status, 200);
    assert.equal((await fetch(`${baseUrl}/api/profile`)).status, 401);
    assert.equal((await fetch(`${baseUrl}/api/notification-preferences`)).status, 401);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
