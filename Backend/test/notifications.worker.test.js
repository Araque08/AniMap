const test = require('node:test');
const assert = require('node:assert/strict');

test('OIDC worker rejects missing configuration, invalid tokens and other identities before processing', async () => {
  const { createWorkerHandler } = require('../src/modules/notifications/notifications.worker');
  let calls = 0;
  const service = { drain: async () => { calls++; return { enabled: true, completed: true }; } };
  const run = async (options, header) => {
    const response = { status(code) { this.code = code; return this; }, json(body) { this.body = body; } };
    await createWorkerHandler({ service, ...options })({ get: () => header }, response);
    return response;
  };
  const config = { audience: 'https://animap.example', serviceAccount: 'worker@example.iam.gserviceaccount.com' };
  assert.equal((await run({ audience: '', serviceAccount: '', service }, '')).code, 503);
  assert.equal((await run(config, '')).code, 401);
  assert.equal((await run({ ...config, verify: async () => { throw Error('private-token'); } }, 'Bearer fixture')).code, 401);
  for (const payload of [{ email: 'someone@example.com', email_verified: true },
    { email: config.serviceAccount, email_verified: false }]) {
    assert.equal((await run({ ...config, verify: async () => payload }, 'Bearer fixture')).code, 403);
  }
  assert.equal(calls, 0);
  const response = await run({ ...config, verify: async (token, audience) => {
    assert.equal(token, 'fixture'); assert.equal(audience, config.audience);
    return { email: config.serviceAccount, email_verified: true };
  } }, 'Bearer fixture');
  assert.equal(response.code, 200); assert.equal(calls, 1);
  assert.doesNotMatch(JSON.stringify(response.body), /fixture|private-token/);
});
