const test = require('node:test');
const assert = require('node:assert/strict');
const { createSightingsService } = require('../src/modules/sightings/sightings.service');

function setup({ wake, commitFails = false, intentFails = false } = {}) {
  const events = [];
  const client = {
    async query(sql) {
      const q = sql.trim().replace(/\s+/g, ' ');
      if (q === 'BEGIN' || q === 'COMMIT' || q === 'ROLLBACK') {
        events.push(q);
        if (q === 'COMMIT' && commitFails) throw new Error('mock PG failure');
        return { rows: [], rowCount: 0 };
      }
      if (q.startsWith('SELECT r.id')) return { rowCount: 1,
        rows: [{ id: 8, estado: 'ACTIVO', mascota_estado: 'PERDIDA' }] };
      if (q.startsWith('INSERT INTO avistamiento')) return { rows: [{ id: 41 }] };
      if (q.startsWith('SELECT a.id')) return { rowCount: 1, rows: [{
        id: 41, descripcion: 'Avistamiento de prueba', fk_reporte_perdida: 8,
        fecha_hora: '2026-11-01T00:00:00.000Z', metodo: 'MAPA', lat: 4.65,
        lng: -74.11, precision_m: null, storage_ref: 'mock-image', reporte_id: 8,
      }] };
      return { rows: [], rowCount: 1 };
    },
    release() { events.push('release'); },
  };
  const images = {
    async saveSightingImage() { return { storageRef: 'mock-image', urlPreview: '/mock' }; },
    async deleteSightingImage() { events.push('delete-image'); },
  };
  const notifications = {
    async recordIntent(queryable, sightingId) {
      assert.equal(queryable, client);
      assert.equal(sightingId, 41);
      events.push('intent');
      if (intentFails) throw new Error('mock intention persistence failure');
    },
    wake() { events.push('wake'); return wake?.(); },
  };
  const service = createSightingsService({ connect: async () => client }, images,
    { validateAllowedArea() {} }, notifications);
  const create = () => service.createSighting(7, {
    reportId: 8, descripcion: 'Avistamiento de prueba', metodo: 'MAPA',
    lat: 4.65, lng: -74.11,
  }, { buffer: Buffer.from('mock') });
  return { events, create };
}

test('persiste la intención en la transacción y despierta envíos después de COMMIT y release', async () => {
  const h = setup();
  assert.equal((await h.create()).id, 41);
  assert.deepEqual(h.events, ['BEGIN', 'intent', 'COMMIT', 'release', 'wake']);
});

test('la solicitud espera el despacho inline tras COMMIT y release', async () => {
  let finish;
  const h = setup({ wake: () => new Promise(resolve => { finish = resolve; }) });
  let completed = false;
  const request = h.create().then(value => { completed = true; return value; });
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(h.events, ['BEGIN', 'intent', 'COMMIT', 'release', 'wake']);
  assert.equal(completed, false);
  finish();
  assert.equal((await request).id, 41);
  assert.equal(completed, true);
});

test('un fallo síncrono del notificador posterior al COMMIT conserva avistamiento y foto', async () => {
  const h = setup({ wake() { throw new Error('mock notification failure'); } });
  assert.equal((await h.create()).id, 41);
  assert.ok(h.events.includes('wake'));
  assert.ok(!h.events.includes('ROLLBACK'));
  assert.ok(!h.events.includes('delete-image'));
});

test('un rechazo asíncrono del notificador no cambia el éxito de creación', async () => {
  const h = setup({ wake: () => Promise.reject(new Error('mock FCM failure')) });
  assert.equal((await h.create()).id, 41);
  await new Promise(setImmediate);
  assert.ok(h.events.includes('wake'));
  assert.ok(!h.events.includes('ROLLBACK'));
  assert.ok(!h.events.includes('delete-image'));
});

test('COMMIT fallido compensa la foto y nunca despacha notificaciones', async () => {
  const h = setup({ commitFails: true });
  await assert.rejects(h.create(), /mock PG failure/);
  assert.ok(!h.events.includes('wake'));
  assert.ok(h.events.includes('ROLLBACK'));
  assert.ok(h.events.includes('delete-image'));
});

test('una intención no persistida revierte la creación aún no confirmada', async () => {
  const h = setup({ intentFails: true });
  await assert.rejects(h.create(), /mock intention persistence failure/);
  assert.ok(h.events.includes('ROLLBACK'));
  assert.ok(!h.events.includes('COMMIT'));
  assert.ok(!h.events.includes('wake'));
});
