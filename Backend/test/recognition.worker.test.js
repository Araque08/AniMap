const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { PassThrough, Writable } = require('node:stream');
const { RecognitionWorker } = require('../src/modules/recognition/recognition.worker');

function fixture() {
  const children = [], writes = []; let reply = true, malformed = false, deferred = false;
  const worker = new RecognitionWorker({ timeoutMs: 15, spawnProcess: (_, args, options) => {
    assert.equal(options.shell, false); assert.equal(options.env.JWT_ACCESS_SECRET, undefined);
    const child = new EventEmitter(); child.stdout = new PassThrough(); child.killed = false;
    child.kill = () => { child.killed = true; };
    child.stdin = new Writable({ write(chunk, __, callback) {
      const request = JSON.parse(String(chunk));
      if (deferred) writes.push(callback); else callback();
      if (reply) queueMicrotask(() => child.stdout.write(malformed ? 'invalid-json\n'
        : JSON.stringify({ id: request.id, queryId: 'fixture-query', similarity: 0.9 }) + '\n'));
    } });
    children.push(child); return child;
  } });
  return { worker, children, writes, setDeferred: () => { deferred = true; },
    setReply: value => { reply = value; }, setMalformed: () => { malformed = true; } };
}
test('persistent transport reuses one child and does not inherit credentials', async () => {
  const h = fixture();
  try {
    await h.worker.request('query'); await h.worker.request('compare'); await h.worker.request('release');
    assert.equal(h.children.length, 1);
  } finally { h.worker.close(); }
});
test('timeout kills only its own worker and a later request restarts cleanly', async () => {
  const h = fixture(); h.setReply(false);
  await assert.rejects(h.worker.request('query'), { code: 'RECOGNITION_TIMEOUT' });
  assert.equal(h.children[0].killed, true);
  h.setReply(true); await h.worker.request('query');
  assert.equal(h.children.length, 2); h.worker.close();
});
test('malformed output and process exit reject safely without hanging', async () => {
  const h = fixture(); h.setMalformed();
  await assert.rejects(h.worker.request('query'), { code: 'RECOGNITION_UNAVAILABLE' });
  assert.equal(h.children[0].killed, true); h.worker.close();
  const other = fixture(); other.setReply(false); const request = other.worker.request('query');
  other.children[0].emit('exit', 1);
  await assert.rejects(request, { code: 'RECOGNITION_UNAVAILABLE' }); other.worker.close();
});
test('a late pipe error from the timed-out process cannot kill the replacement worker', async () => {
  const h = fixture(); h.setReply(false); h.setDeferred();
  await assert.rejects(h.worker.request('query'), { code: 'RECOGNITION_TIMEOUT' });
  const current = h.worker.request('query');
  h.writes[0](Error('old pipe closed'));
  h.children[1].stdout.write(JSON.stringify({ id: '2', queryId: 'new-query' }) + '\n');
  assert.equal((await current).queryId, 'new-query');
  assert.equal(h.children[1].killed, false); h.worker.close();
});
