const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const express = require('express');
const { createRecognitionService } = require('../src/modules/recognition/recognition.service');
const { createRecognitionRepository } = require('../src/modules/recognition/recognition.repository');
const { createRecognitionRouter } = require('../src/modules/recognition/recognition.routes');

function fixture(options = {}) {
  const photos = [
    { reportId: 1, petId: 11, ownerId: 7, photoId: 'a', nombre: 'QA A' },
    { reportId: 1, petId: 11, ownerId: 7, photoId: 'b', nombre: 'QA A' },
    { reportId: 2, petId: 12, ownerId: 8, photoId: 'c', nombre: 'QA B' },
  ];
  let queries = 0; const actions = [];
  const repo = { activePhotos: async () => ++queries === 1 ? photos : (options.current ?? photos),
    photoBytes: async p => options.missing === p.photoId ? null : Buffer.from(p.photoId) };
  const worker = { request: async (action, payload) => {
    actions.push(action);
    if (action === 'query') return { queryId: 'query-a' };
    if (action === 'release') return {};
    if (options.error) throw Object.assign(Error('private-model-path'), { code: options.error });
    return { similarity: ({ a: 0.85, b: 0.96, c: 0.90 })[Buffer.from(payload.image, 'base64').toString()] };
  }, close() {} };
  return { service: createRecognitionService({ repo, worker, ...options }), repo, worker, photos, actions };
}

test('all photos, best per report, descending order and no owner/bytes in result', async () => {
  const h = fixture(); const result = await h.service.search(Buffer.from('query'));
  assert.equal(result.searchedImages, 3);
  assert.deepEqual(result.matches.map(m => [m.reportId, m.photo.id, m.similarity]), [[1, 'b', 0.96], [2, 'c', 0.90]]);
  assert.doesNotMatch(JSON.stringify(result), /ownerId|base64|query-a/);
  assert.equal(h.actions.filter(a => a === 'compare').length, 3);
});
test('threshold configurable, empty results and no silently relaxed threshold', async () => {
  assert.deepEqual((await fixture({ threshold: 0.99 }).service.search(Buffer.from('x'))).matches, []);
  await assert.rejects(fixture({ threshold: NaN }).service.search(Buffer.from('x')), { code: 'RECOGNITION_UNAVAILABLE' });
});
test('closed report/removed photo after inference cannot remain in response', async () => {
  const h = fixture({ current: [] });
  assert.deepEqual((await h.service.search(Buffer.from('x'))).matches, []);
});
test('photo replaced during inference falls back to the next current photo of that report', async () => {
  const h = fixture(); const reads = new Map();
  h.repo.photoBytes = async p => {
    const n = (reads.get(p.photoId) || 0) + 1; reads.set(p.photoId, n);
    return Buffer.from(p.photoId === 'b' && n > 1 ? 'changed-content' : p.photoId);
  };
  const result = await h.service.search(Buffer.from('x'));
  assert.deepEqual(result.matches.map(m => [m.reportId, m.photo.id]), [[2, 'c'], [1, 'a']]);
});
test('missing and corrupt candidates skipped, model failures propagate', async () => {
  const result = await fixture({ missing: 'b' }).service.search(Buffer.from('x'));
  assert.equal(result.skippedImages, 1); assert.equal(result.matches[0].reportId, 2);
  const damaged = await fixture({ error: 'INVALID_RECOGNITION_IMAGE' }).service.search(Buffer.from('x'));
  assert.equal(damaged.skippedImages, 3); assert.deepEqual(damaged.matches, []);
  await assert.rejects(fixture({ error: 'RECOGNITION_UNAVAILABLE' }).service.search(Buffer.from('x')), { code: 'RECOGNITION_UNAVAILABLE' });
});
test('busy and deadline are bounded and a later request can retry', async () => {
  const h = fixture({ timeoutMs: 20 });
  h.worker.request = async () => new Promise(() => {});
  const first = h.service.search(Buffer.from('x'));
  await assert.rejects(h.service.search(Buffer.from('x')), { code: 'RECOGNITION_BUSY' });
  await assert.rejects(first, { code: 'RECOGNITION_TIMEOUT' });
});
test('relational candidates are active/public; Mongo verifies full binding and ACTIVA', async () => {
  const calls = [];
  const repo = createRecognitionRepository({ pool: { query: async q => { calls.push(q); return { rows: [] }; } },
    mongo: async () => ({ collection: name => ({ findOne: async (filter, options) => {
      calls.push({ name, filter, options }); return { imagen: Buffer.from('fixture') }; } }) }) });
  await repo.activePhotos();
  assert.match(calls[0].text, /r.estado = 'ACTIVO' AND m.estado = 'PERDIDA'/);
  assert.doesNotMatch(calls[0].text, /LIMIT|es_principal = TRUE|WHERE.*fk_usuario = \$/);
  await repo.photoBytes({ photoId: '000000000000000000000001', petId: 11, ownerId: 7 });
  assert.equal(calls[1].filter.mascotaIdPg, 11); assert.equal(calls[1].filter.usuarioIdPg, 7);
  assert.equal(calls[1].filter.estado, 'ACTIVA');
});

test('HTTP endpoint: JWT required, one image, size/MIME validation and sanitized errors', async () => {
  const { signAccessToken } = require('../src/utils/jwt');
  const restore = require('../test-support/auth-fixture.cjs').installAuthFixture({ 7: 'USUARIO' });
  let calls = 0, fail = false;
  const app = express();
  app.use('/api/recognition', createRecognitionRouter({ limiter: (_, __, next) => next(),
    service: { search: async () => { calls++; if (fail) throw Error('private-credential'); return { matches: [] }; } } }));
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}/api/recognition/search`;
  const headers = { Authorization: `Bearer ${signAccessToken({ sub: 7, deviceId: 'fixture-device', role: 'USUARIO' })}` };
  const body = (bytes, name = 'query.png', mime = 'image/png') => {
    const form = new FormData(); form.append('foto', new Blob([bytes], { type: mime }), name); return form;
  };
  try {
    assert.equal((await fetch(url, { method: 'POST' })).status, 401);
    assert.equal((await fetch(url, { method: 'POST', headers })).status, 400);
    assert.equal((await fetch(url, { method: 'POST', headers, body: body('bad') })).status, 400);
    assert.equal((await fetch(url, { method: 'POST', headers, body: body(Buffer.alloc(5 * 1024 * 1024 + 1)) })).status, 413);
    assert.equal(calls, 0);
    const png = Buffer.from('89504e470d0a1a0a', 'hex');
    assert.equal((await fetch(url, { method: 'POST', headers, body: body(png) })).status, 200);
    fail = true;
    const response = await fetch(url, { method: 'POST', headers, body: body(png) });
    assert.equal(response.status, 503); assert.doesNotMatch(await response.text(), /private-credential/);
  } finally { restore(); await new Promise(resolve => server.close(resolve)); }
});
