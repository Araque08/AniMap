const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');

// Exercise the actual combined app, not three separately mounted test routers.
const restoreAuth = require('../test-support/auth-fixture.cjs').installAuthFixture({ 7: 'USUARIO' });
const app = require('../src/app');
const { signAccessToken } = require('../src/utils/jwt');
let server, base;

test.before(async () => {
  server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  base = `http://127.0.0.1:${server.address().port}/api`;
});
test.after(async () => {
  await new Promise(resolve => server.close(resolve));
  restoreAuth();
});

test('combined API keeps health, recognition authentication and photo ownership middleware', async () => {
  assert.equal((await fetch(`${base}/health`)).status, 200);
  for (const [path, method] of [['/recognition/search', 'POST'], ['/pets/9/images/batch', 'PUT']]) {
    const response = await fetch(base + path, { method });
    assert.equal(response.status, 401);
    assert.equal((await response.json()).code, 'ACCESS_TOKEN_REQUIRED');
  }
});

test('combined recognition route validates input before model or storage calls', async () => {
  const response = await fetch(`${base}/recognition/search`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${signAccessToken({ sub: 7, deviceId: 'fixture-device', role: 'USUARIO' })}` },
  });
  assert.equal(response.status, 400);
  assert.equal((await response.json()).code, 'INVALID_RECOGNITION_IMAGE');
});

test('combined API retains the protected scheduled notification endpoint', async () => {
  const response = await fetch(`${base}/internal/notifications/process`, { method: 'POST' });
  assert.equal(response.status, 503);
  assert.equal((await response.json()).code, 'WORKER_NOT_CONFIGURED');
});
