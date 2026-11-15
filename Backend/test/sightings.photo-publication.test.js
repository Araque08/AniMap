const test = require('node:test');
const assert = require('node:assert/strict');
const { createSightingsService } = require('../src/modules/sightings/sightings.service');
const { createSightingSchema } = require('../src/modules/sightings/sightings.schemas');

const data = { descripcion: 'Foto QA aislada', reportId: null, metodo: 'MAPA', lat: 4.65, lng: -74.11,
  solicitudId: '790ec1af-182b-4fa6-9320-df8bc0c29207', ubicacionConfirmada: true, compartirContacto: false };
const file = { buffer: Buffer.from([255,216,255,1]), mimetype: 'image/jpeg', originalname: 'qa.jpg' };

function setup({ existing, crash = false } = {}) {
  const log = [], jobs = [];
  const client = {
    async query(sql) {
      log.push(sql.trim().replace(/\s+/g, ' '));
      if (sql.includes('INSERT INTO avistamiento')) return { rows: [{ id: 41 }], rowCount: 1 };
      if (sql.includes('SELECT') && sql.includes('a.id')) return { rows: [{ id: 41, fk_reporte_perdida: null,
        fecha_hora: '2026-11-08T00:00:00Z', lat: 4.65, lng: -74.11, metodo: 'MAPA' }], rowCount: 1 };
      return { rows: [], rowCount: 0 };
    }, release() { log.push('release'); },
  };
  const matches = { enabled: true,
    async findRequest() { return existing?.(jobs); },
    async enqueue(_, job) { log.push('enqueue'); jobs.push(job); },
    async wake() { log.push('analyze'); if (crash) throw new Error('model offline'); },
  };
  const images = { async saveSightingImage() { log.push('mongo-save'); return { storageRef: 'photo' }; },
    async deleteSightingImage() { log.push('mongo-delete'); } };
  const notifications = { async recordIntent() { log.push('legacy'); }, async wake() { log.push('push'); } };
  const service = createSightingsService({ connect: async () => client }, images,
    { validateAllowedArea() {} }, notifications, matches);
  return { log, jobs, service };
}

test('schema acepta clave UUID y consentimiento explícito, rechaza similitud del cliente', () => {
  assert.equal(createSightingSchema.safeParse(data).success, true);
  assert.equal(createSightingSchema.safeParse({ ...data, similarity: .99 }).success, false);
  assert.equal(createSightingSchema.safeParse({ ...data, solicitudId: 'bad' }).success, false);
  assert.equal(createSightingSchema.safeParse({ ...data, compartirContacto: 'arbitrary' }).success, false);
});

test('foto sin ubicación confirmada se rechaza antes de guardar en MongoDB', async () => {
  const h = setup();
  await assert.rejects(h.service.createSighting(7, { ...data, ubicacionConfirmada: false }, file), e => e.statusCode === 400);
  assert.ok(!h.log.includes('mongo-save'));
});

test('foto sin clave idempotente no guarda fotografías ni registros', async () => {
  const h = setup();
  await assert.rejects(h.service.createSighting(7, { ...data, solicitudId: undefined }, file), e => e.statusCode === 400);
  assert.ok(!h.log.includes('mongo-save'));
});

test('publicación persiste trabajo en transacción y analiza únicamente después del COMMIT', async () => {
  const h = setup(); assert.equal((await h.service.createSighting(7, data, file)).id, 41);
  assert.ok(h.log.indexOf('enqueue') < h.log.indexOf('COMMIT'));
  assert.ok(h.log.indexOf('COMMIT') < h.log.indexOf('analyze'));
  assert.equal(h.log.filter(v => v === 'mongo-save').length, 1);
  assert.ok(!h.log.includes('legacy'));
});

test('reintento HTTP reutiliza avistamiento sin guardar segunda foto; otros datos dan 409', async () => {
  let original;
  const h = setup({ existing: () => original });
  await h.service.createSighting(7, data, file);
  original = { sightingId: 41, fingerprint: h.jobs[0].fingerprint };
  await h.service.createSighting(7, data, file);
  assert.equal(h.log.filter(v => v === 'mongo-save').length, 1);
  await assert.rejects(h.service.createSighting(7, { ...data, descripcion: 'otra observación' }, file), e => e.statusCode === 409);
});

test('fallo de reconocimiento después del COMMIT nunca compensa la foto válida', async () => {
  const h = setup({ crash: true }); assert.equal((await h.service.createSighting(7, data, file)).id, 41);
  await new Promise(setImmediate);
  assert.ok(!h.log.includes('mongo-delete')); assert.ok(!h.log.includes('ROLLBACK'));
});
