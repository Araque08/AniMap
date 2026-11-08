const test = require('node:test');
const assert = require('node:assert/strict');
const { createNotificationsService } = require('../src/modules/notifications/notifications.service');

test('scheduled: startup and sighting wake do no background work; authenticated drain recovers', async () => {
  let recoveries = 0;
  const service = createNotificationsService({ enabled: true, testMode: false,
    processingMode: 'scheduled', repo: {
      recoverAbandoned: async () => { recoveries++; return []; },
      pendingNotifications: async () => [],
    } });
  service.start(); service.wake();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(recoveries, 0);
  assert.deepEqual(await service.drain(), { enabled: true, completed: true });
  assert.equal(recoveries, 1);
  service.stop();
});

test('disabled or invalid processing mode cannot access pending work', async () => {
  for (const config of [{ enabled: false }, { enabled: true, processingMode: 'invalid' }]) {
    const service = createNotificationsService({ testMode: false, ...config,
      repo: { recoverAbandoned: () => assert.fail('must not touch database') } });
    assert.deepEqual(await service.drain(), { enabled: false, completed: true });
  }
});

test('scheduled failure is reported to caller without exposing driver details', async () => {
  const warnings = [];
  const service = createNotificationsService({ enabled: true, testMode: false,
    processingMode: 'scheduled', repo: { recoverAbandoned: async () => {
      throw new Error('private-registration');
    } }, logger: { warn: (...args) => warnings.push(args) } });
  assert.deepEqual(await service.drain(), { enabled: true, completed: false });
  assert.doesNotMatch(JSON.stringify(warnings), /private-registration/);
});
