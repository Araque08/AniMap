const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');

test('Cloud Run shutdown stops worker and HTTP before closing storage, once', async () => {
  const { startServer } = require('../src/server');
  const calls = [];
  const signals = new EventEmitter();
  const server = new EventEmitter();
  server.close = callback => { calls.push('http-close'); callback(); };
  const instance = await startServer({
    application: { listen: () => { queueMicrotask(() => server.emit('listening')); return server; } },
    database: { query: async () => {}, end: async () => calls.push('pg-close') },
    worker: { start: () => calls.push('start'), stop: () => calls.push('stop') },
    closeImages: async () => calls.push('mongo-close'), signals, exit: code => calls.push(`exit-${code}`),
  });
  await Promise.all([instance.shutdown(), instance.shutdown()]);
  assert.deepEqual(calls, ['start', 'stop', 'http-close', 'pg-close', 'mongo-close', 'exit-0']);
  assert.equal(signals.listenerCount('SIGTERM'), 0);
});
