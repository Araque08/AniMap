const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');

const app = require('../src/app');
const { signAccessToken } = require('../src/utils/jwt');
const { createSightingsService } = require('../src/modules/sightings/sightings.service');

function historyRow({
  reportId = 51,
  status = 'ACTIVO',
  sightingId = 91,
  date = '2026-09-13T17:00:00.000Z',
  photo = null,
  total = 1,
} = {}) {
  return {
    reporte_id: reportId,
    reporte_estado: status,
    mascota_id: 31,
    mascota_nombre: 'Luna',
    especie_nombre: 'Perro',
    raza_nombre: 'Criollo',
    perdida_metodo: 'MAPA',
    perdida_lat: '4.6569',
    perdida_lng: '-74.1095',
    perdida_precision_m: null,
    mascota_foto_storage_ref: 'pet-photo',
    mascota_foto_url_preview: '/api/pets/images/pet-photo',
    total_avistamientos: total,
    avistamiento_id: sightingId,
    avistamiento_descripcion: sightingId == null ? null : `Avistamiento ${sightingId}`,
    avistamiento_fecha_hora: sightingId == null ? null : date,
    avistamiento_metodo: sightingId == null ? null : 'GPS',
    avistamiento_lat: sightingId == null ? null : '4.6570',
    avistamiento_lng: sightingId == null ? null : '-74.1090',
    avistamiento_precision_m: sightingId == null ? null : '7.5',
    avistamiento_foto_storage_ref: photo,
    avistamiento_foto_url_preview: photo
      ? `/api/sightings/images/${photo}`
      : null,
  };
}

function poolReturning(rows) {
  const calls = [];
  return {
    calls,
    async query(sql, params) {
      const normalized = sql.trim().replace(/\s+/g, ' ');
      calls.push({ sql: normalized, params });
      return { rowCount: rows.length, rows };
    },
  };
}

test('1 dueño consulta el historial de su reporte', async () => {
  const pool = poolReturning([historyRow()]);
  const result = await createSightingsService(pool, {}).getReportHistory(7, 51);
  assert.equal(result.report.id, 51);
  assert.equal(result.sightings.length, 1);
  assert.deepEqual(pool.calls[0].params, [51, 7]);
  assert.match(pool.calls[0].sql, /r\.fk_usuario = \$2/);
});

test('2 usuario ajeno recibe 404 sin revelar el reporte', async () => {
  const pool = poolReturning([]);
  await assert.rejects(
    createSightingsService(pool, {}).getReportHistory(8, 51),
    (error) => error.statusCode === 404 && error.message === 'Reporte no encontrado',
  );
});

test('3 reporte inexistente recibe el mismo 404', async () => {
  const pool = poolReturning([]);
  await assert.rejects(
    createSightingsService(pool, {}).getReportHistory(7, 999),
    (error) => error.statusCode === 404 && error.message === 'Reporte no encontrado',
  );
});

test('4 historial vacío devuelve lista vacía y contador cero', async () => {
  const pool = poolReturning([historyRow({ sightingId: null, total: 0 })]);
  const result = await createSightingsService(pool, {}).getReportHistory(7, 51);
  assert.deepEqual(result.sightings, []);
  assert.equal(result.total, 0);
  assert.equal(result.filteredTotal, 0);
});

test('5 consulta solo avistamientos del reportId exacto', async () => {
  const pool = poolReturning([historyRow({ reportId: 77 })]);
  await createSightingsService(pool, {}).getReportHistory(7, 77);
  assert.match(pool.calls[0].sql, /a\.fk_reporte_perdida = r\.id/);
  assert.deepEqual(pool.calls[0].params, [77, 7]);
});

test('6 dos reportes de la misma mascota no mezclan historial', async () => {
  const firstPool = poolReturning([historyRow({ reportId: 51, sightingId: 91 })]);
  const secondPool = poolReturning([historyRow({ reportId: 52, sightingId: 92 })]);
  const first = await createSightingsService(firstPool, {}).getReportHistory(7, 51);
  const second = await createSightingsService(secondPool, {}).getReportHistory(7, 52);
  assert.deepEqual(first.sightings.map((item) => item.id), [91]);
  assert.deepEqual(second.sightings.map((item) => item.id), [92]);
  assert.notDeepEqual(firstPool.calls[0].params, secondPool.calls[0].params);
});

test('7 reporte ACTIVO permite consulta', async () => {
  const result = await createSightingsService(
    poolReturning([historyRow({ status: 'ACTIVO' })]),
    {},
  ).getReportHistory(7, 51);
  assert.equal(result.report.estado, 'ACTIVO');
});

test('8 reporte FINALIZADO permite consulta histórica', async () => {
  const result = await createSightingsService(
    poolReturning([historyRow({ status: 'FINALIZADO' })]),
    {},
  ).getReportHistory(7, 51);
  assert.equal(result.report.estado, 'FINALIZADO');
});

test('9 el orden solicitado es más reciente primero con desempate por ID', async () => {
  const pool = poolReturning([
    historyRow({ sightingId: 92, date: '2026-09-13T18:00:00.000Z', total: 2 }),
    historyRow({ sightingId: 91, date: '2026-09-13T17:00:00.000Z', total: 2 }),
  ]);
  const result = await createSightingsService(pool, {}).getReportHistory(7, 51);
  assert.deepEqual(result.sightings.map((item) => item.id), [92, 91]);
  assert.match(pool.calls[0].sql, /ORDER BY a\.fecha_hora DESC NULLS LAST, a\.id DESC/);
});

test('10 foto opcional devuelve solo ID y URL segura', async () => {
  const result = await createSightingsService(
    poolReturning([historyRow({ photo: 'mongo-photo' })]),
    {},
  ).getReportHistory(7, 51);
  assert.deepEqual(result.sightings[0].foto, {
    id: 'mongo-photo',
    url: '/api/sightings/images/mongo-photo',
  });
});

test('11 avistamiento sin foto devuelve foto null', async () => {
  const result = await createSightingsService(
    poolReturning([historyRow()]),
    {},
  ).getReportHistory(7, 51);
  assert.equal(result.sightings[0].foto, null);
});

test('12 respuesta no expone identidad ni contacto del autor', async () => {
  const result = await createSightingsService(
    poolReturning([historyRow()]),
    {},
  ).getReportHistory(7, 51);
  const serialized = JSON.stringify(result);
  for (const forbidden of ['fk_usuario', 'userId', 'reporter', 'email', 'telefono']) {
    assert.ok(!serialized.includes(forbidden));
  }
});

test('13 filtro Hoy usa inicio del día en Bogotá convertido a UTC', async () => {
  const pool = poolReturning([historyRow()]);
  await createSightingsService(pool, {}).getReportHistory(7, 51, 'TODAY');
  assert.match(pool.calls[0].sql, /date_trunc\('day'.*America\/Bogota/);
  assert.match(pool.calls[0].sql, />=/);
});

test('14 filtro 7 días se calcula desde NOW UTC', async () => {
  const pool = poolReturning([historyRow()]);
  await createSightingsService(pool, {}).getReportHistory(7, 51, '7D');
  assert.match(pool.calls[0].sql, /INTERVAL '7 days'/);
});

test('15 borde exacto de 7 días se incluye con >=', async () => {
  const pool = poolReturning([historyRow()]);
  await createSightingsService(pool, {}).getReportHistory(7, 51, '7D');
  assert.match(pool.calls[0].sql, /a\.fecha_hora >= .*INTERVAL '7 days'/);
});

test('16 filtro 30 días se calcula desde NOW UTC', async () => {
  const pool = poolReturning([historyRow()]);
  await createSightingsService(pool, {}).getReportHistory(7, 51, '30D');
  assert.match(pool.calls[0].sql, /INTERVAL '30 days'/);
});

test('17 borde exacto de 30 días se incluye con >=', async () => {
  const pool = poolReturning([historyRow()]);
  await createSightingsService(pool, {}).getReportHistory(7, 51, '30D');
  assert.match(pool.calls[0].sql, /a\.fecha_hora >= .*INTERVAL '30 days'/);
});

test('18 query param inválido recibe rechazo controlado', async () => {
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const address = server.address();
    const token = signAccessToken({ sub: '7', deviceId: 'history-test' });
    const response = await fetch(
      `http://127.0.0.1:${address.port}/api/reports/51/sightings?period=YEAR`,
      { headers: { Authorization: `Bearer ${token}` } },
    );
    assert.equal(response.status, 400);
    assert.match((await response.json()).message, /Período inválido/);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
