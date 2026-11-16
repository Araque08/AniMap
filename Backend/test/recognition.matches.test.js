const test = require('node:test');
const assert = require('node:assert/strict');
const { createMatchService } = require('../src/modules/recognition/recognition.matches.service');
const { createMatchRepository } = require('../src/modules/recognition/recognition.matches.repository');

test('detalle privado entrega descripción y la fotografía original del avistamiento', async () => {
  const original = Buffer.from('synthetic-sighting-original');
  const repo = createMatchRepository({ pool: { query: async () => ({ rows: [{
    id: 12, reportId: 23, sightingId: 41, userId: 7,
    photoId: '507f1f77bcf86cd799439011', similitud: 91, umbral_usado: 80,
    description: 'Avistamiento QA junto al parque',
  }] }) }, mongo: async () => ({ collection: name => {
    assert.equal(name, 'ImagenAvistamiento');
    return { findOne: async filter => {
      assert.equal(filter.avistamientoIdPg, 41);
      assert.equal(filter.usuarioIdPg, 7);
      return { imagen: original, mimeType: 'image/png' };
    } };
  } }) });
  assert.equal((await repo.detail(101, 12)).description, 'Avistamiento QA junto al parque');
  assert.deepEqual((await repo.image(101, 12)).buffer, original);
});

function harness({ matches, selectedReportId = 1, event = {}, searchError, enabled = true, current = true, attempts = 1 } = {}) {
  const calls = [], records = [];
  let available = true;
  const job = { sightingId: 41, userId: 7, claimId: 'lease', attempts };
  const repo = {
    async claim() { if (!available) return null; available = false; return job; },
    async photo() { return Buffer.from('isolated-photo'); },
    async selectedReport() { return selectedReportId; },
    async transaction(fn) { calls.push('BEGIN'); const r = await fn(repo); calls.push('COMMIT'); return r; },
    async isCurrent() { return current; },
    async candidate(_, sightingId, reportId) { return { sightingId, reportId, ownerId: reportId + 100,
      authorId: 7, reportState: 'ACTIVO', petState: 'PERDIDA', ownerActive: true,
      ownerVerified: true, notificationsEnabled: true, ...event }; },
    async saveMatch(_, e, data) { records.push({ ...e, ...data }); return records.length; },
    async complete() { calls.push('complete'); },
    async fail(_, j, code, options) { calls.push(code); return options?.permanent || j.attempts >= 3; },
    async list(ownerId, before) { return [ownerId, before]; },
    async detail(ownerId, id) { return ownerId === 101 ? { id } : null; },
    async image(ownerId) { return ownerId === 101 ? { buffer: Buffer.from('photo'), mimeType: 'image/jpeg' } : null; },
  };
  const notifications = {
    allowsEvent: () => true,
    async recordMatchIntent() { calls.push('match-intent'); return 12; },
    async recordIntent() { calls.push('legacy-fallback'); },
    async wake() { calls.push('send-after-commit'); },
  };
  const recognizer = { async search(content, options) {
    calls.push({ content, options });
    if (searchError) throw Object.assign(new Error('private detail not logged'), { code: searchError });
    return { model: 'resnet50-imagenet1k-v2', threshold: .8, matches: matches ?? [
      { reportId: 1, photo: { id: 'photo-1' }, similarity: .83 },
    ] };
  } };
  const service = createMatchService({ repo, recognizer, notifications, enabled, processingMode: 'inline',
    logger: { warn: (_, safe) => calls.push(safe.code) } });
  return { service, records, calls, repo, notifications };
}

test('publicación > umbral conserva posible coincidencia; 83% no confirma identidad', async () => {
  const h = harness(); await h.service.drain();
  assert.equal(h.records.length, 1); assert.equal(h.records[0].similarity, .83);
  assert.equal(h.records[0].model, 'resnet50-imagenet1k-v2');
  assert.ok(h.calls.indexOf('COMMIT') < h.calls.indexOf('send-after-commit'));
});

test('similitud bajo el umbral no genera evento; conserva alerta vinculada anterior', async () => {
  const h = harness({ matches: [{ reportId: 1, photo: { id: 'x' }, similarity: .79 }] });
  await h.service.drain(); assert.equal(h.records.length, 0); assert.ok(h.calls.includes('legacy-fallback'));
});

test('solo el reporte seleccionado recibe coincidencia aunque otros tengan mayor similitud', async () => {
  const h = harness({ selectedReportId: 3, matches: [1, 2, 3, 4, 5].map(reportId => ({
    reportId, photo: { id: 'x' }, similarity: .99 - reportId / 100,
  })) });
  await h.service.drain();
  assert.deepEqual(h.records.map(r => r.reportId), [3]);
  assert.equal(h.calls.find(c => c.options)?.options.reportId, 3);
  assert.deepEqual(h.calls.find(c => c.content)?.content, Buffer.from('isolated-photo'));
});

test('un avistamiento independiente conserva su publicación sin análisis ni avisos a terceros', async () => {
  const h = harness({ selectedReportId: null });
  await h.service.drain();
  assert.equal(h.records.length, 0);
  assert.equal(h.calls.filter(c => c.options).length, 0);
  assert.ok(h.calls.includes('complete'));
});

test('otro reporte sobre el umbral no sustituye al seleccionado sin coincidencia', async () => {
  const h = harness({ selectedReportId: 3, matches: [{ reportId: 2, photo: { id: 'x' }, similarity: .99 }] });
  await h.service.drain();
  assert.equal(h.records.length, 0);
  assert.ok(h.calls.includes('legacy-fallback'));
});

for (const [name, event] of [
  ['reporte finalizado', { reportState: 'FINALIZADO' }],
  ['propio avistamiento', { ownerId: 7 }],
  ['preferencias desactivadas', { notificationsEnabled: false }],
  ['filtro especie', { speciesFilter: 'Gato', species: 'Perro' }],
  ['filtro tipo', { eventFilter: 'PERDIDA' }],
  ['zona sin coordenadas', { onlyMyZone: true, lat: null }],
]) test(`${name} no crea alerta ni evento ajeno`, async () => {
  const h = harness({ event }); await h.service.drain(); assert.equal(h.records.length, 0);
});

test('aislamiento QA se comprueba antes de persistir eventos', async () => {
  const h = harness(); h.notifications.allowsEvent = () => false;
  await h.service.drain(); assert.equal(h.records.length, 0);
});

test('lease antiguo no persiste eventos después de recuperación por otro proceso', async () => {
  const h = harness({ current: false }); await h.service.drain();
  assert.equal(h.records.length, 0); assert.ok(!h.calls.includes('complete'));
});

test('foto inexistente: fallo definitivo, fallback vinculado; no borra imagen ni avistamiento', async () => {
  const h = harness(); h.repo.photo = async () => null;
  await h.service.drain(); assert.equal(h.records.length, 0);
  assert.ok(h.calls.includes('MATCH_PHOTO_UNAVAILABLE')); assert.ok(h.calls.includes('legacy-fallback'));
});

test('fallo temporal: persiste reintento; al agotar intentos conserva ANIMAP-35', async () => {
  const first = harness({ searchError: 'RECOGNITION_BUSY' }); await first.service.drain();
  assert.ok(first.calls.includes('RECOGNITION_BUSY')); assert.ok(!first.calls.includes('legacy-fallback'));
  const last = harness({ searchError: 'RECOGNITION_TIMEOUT', attempts: 3 }); await last.service.drain();
  assert.ok(last.calls.includes('legacy-fallback'));
});

test('dos despertares concurrentes no procesan el mismo trabajo dos veces', async () => {
  const h = harness(); await Promise.all([h.service.drain(), h.service.drain()]); assert.equal(h.records.length, 1);
});

test('deshabilitado no consulta trabajos ni invoca reconocimiento', async () => {
  const h = harness({ enabled: false }); h.repo.claim = () => assert.fail('no consulta');
  assert.equal((await h.service.drain()).enabled, false);
});

test('detalle, foto e historial privados: ownership del repositorio es obligatorio', async () => {
  const h = harness(); assert.deepEqual(await h.service.detail(101, 1), { id: 1 });
  await assert.rejects(h.service.detail(102, 1), e => e.statusCode === 404);
  await assert.rejects(h.service.image(102, 1), e => e.statusCode === 404);
  assert.deepEqual(await h.service.list(101, 5), [101, 5]);
});
