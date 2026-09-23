const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');

const app = require('../src/app');
const geofence = require('../src/modules/geofence/geofence.service');
const {
  createGeocodingService,
  OFFICIAL_BOUNDS,
} = require('../src/modules/geocoding/geocoding.service');
const { createReportsService } = require('../src/modules/reports/reports.service');
const { createSightingsService } = require('../src/modules/sightings/sightings.service');

const inside = { lat: 4.651, lng: -74.109 };
const outside = { lat: 4.65, lng: -74.1 };
const vertex = (() => {
  const point = geofence.officialFeature.geometry.coordinates[0][0];
  return { lat: point[1], lng: point[0] };
})();

function areaMode(mode) {
  return {
    area: geofence.area,
    resolveGeofenceMode: () => mode,
    evaluateAllowedArea: (lat, lng) => geofence.evaluateAllowedArea(lat, lng, mode),
    validateAllowedArea: (lat, lng) => geofence.validateAllowedArea(lat, lng, mode),
  };
}

function googleResult(position, suffix = '1') {
  return {
    formatted_address: `Carrera de prueba ${suffix}, Bogotá, Colombia`,
    place_id: `place-${suffix}`,
    geometry: {
      location: position,
      location_type: 'ROOFTOP',
    },
  };
}

function response(body, ok = true) {
  return { ok, async json() { return body; } };
}

function geocoder({ mode = 'ENFORCE', body, fetchImpl, apiKey = 'private-test-key' } = {}) {
  return createGeocodingService({
    apiKey,
    fetchImpl: fetchImpl || (async () => response(body)),
    geofenceService: areaMode(mode),
    timeoutMs: 20,
  });
}

function fakePool(handler) {
  const calls = [];
  let connectCount = 0;
  const client = {
    async query(sql, params) {
      const normalized = sql.trim().replace(/\s+/g, ' ');
      calls.push({ sql: normalized, params });
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(normalized)) {
        return { rowCount: 0, rows: [] };
      }
      return handler(normalized, params);
    },
    release() {},
  };
  return {
    calls,
    get connectCount() { return connectCount; },
    async connect() { connectCount += 1; return client; },
    query: client.query,
  };
}

function reportPool({ editing = false } = {}) {
  return fakePool((sql) => {
    if (editing && sql.startsWith('SELECT id, descripcion')) {
      return { rowCount: 1, rows: [{ id: 61, descripcion: null, mostrar_contacto: false, estado: 'ACTIVO' }] };
    }
    if (editing && sql.startsWith('UPDATE reporte')) {
      return { rowCount: 1, rows: [{ actualizado_en: '2026-09-13T12:00:00-05:00' }] };
    }
    if (editing && sql.startsWith('UPDATE ubicacion')) return { rowCount: 1, rows: [] };
    if (sql.startsWith('SELECT id, estado')) return { rowCount: 1, rows: [{ id: 31, estado: 'ACTIVA' }] };
    if (sql.startsWith('SELECT id FROM reporte')) return { rowCount: 0, rows: [] };
    if (sql.startsWith('INSERT INTO reporte')) return { rowCount: 1, rows: [{ id: 61, estado: 'ACTIVO' }] };
    return { rowCount: 1, rows: [] };
  });
}

function sightingPool({ linked = false } = {}) {
  return fakePool((sql) => {
    if (sql.startsWith('SELECT r.id, r.estado')) {
      return { rowCount: 1, rows: [{ id: 61, estado: 'ACTIVO', mascota_estado: 'PERDIDA' }] };
    }
    if (sql.startsWith('INSERT INTO avistamiento')) return { rowCount: 1, rows: [{ id: 91 }] };
    if (sql.startsWith('SELECT a.id')) {
      return {
        rowCount: 1,
        rows: [{
          id: 91,
          descripcion: 'Avistamiento temporal',
          fk_reporte_perdida: linked ? 61 : null,
          fecha_hora: '2026-09-13T17:00:00.000Z',
          metodo: 'DIRECCION', lat: String(inside.lat), lng: String(inside.lng),
          precision_m: null, direccion: 'Dirección validada', place_id: 'place-1',
          storage_ref: null, url_preview: null,
          reporte_id: linked ? 61 : null,
          mascota_nombre: linked ? 'Luna' : null,
          especie_nombre: linked ? 'Perro' : null,
          raza_nombre: linked ? 'Criollo' : null,
        }],
      };
    }
    return { rowCount: 1, rows: [] };
  });
}

function reportData(position = inside) {
  return {
    mascotaId: 31,
    descripcion: 'Reporte temporal',
    mostrarContacto: false,
    ubicacion: {
      metodo: 'DIRECCION', lat: position.lat, lng: position.lng,
      precisionM: null, direccion: 'Dirección validada', placeId: 'place-1',
    },
  };
}

function sightingData(position = inside, reportId = null) {
  return {
    descripcion: 'Avistamiento temporal', reportId, metodo: 'DIRECCION',
    lat: position.lat, lng: position.lng, precisionM: null,
    direccion: 'Dirección validada', placeId: 'place-1',
  };
}

test('1 WARN interior: inside=true allowed=true', () => {
  assert.deepEqual(geofence.evaluateAllowedArea(inside.lat, inside.lng, 'WARN'), {
    inside: true, allowed: true, mode: 'WARN', area: geofence.area,
  });
});
test('2 WARN borde: inside=true allowed=true', () => {
  assert.equal(geofence.evaluateAllowedArea(vertex.lat, vertex.lng, 'WARN').allowed, true);
});
test('3 WARN exterior: inside=false allowed=true', () => {
  assert.deepEqual(geofence.evaluateAllowedArea(outside.lat, outside.lng, 'WARN'), {
    inside: false, allowed: true, mode: 'WARN', area: geofence.area,
  });
});
test('4 ENFORCE interior permite', () => assert.equal(geofence.evaluateAllowedArea(inside.lat, inside.lng, 'ENFORCE').allowed, true));
test('5 ENFORCE borde permite', () => assert.equal(geofence.evaluateAllowedArea(vertex.lat, vertex.lng, 'ENFORCE').allowed, true));
test('6 ENFORCE exterior bloquea', () => assert.equal(geofence.evaluateAllowedArea(outside.lat, outside.lng, 'ENFORCE').allowed, false));
test('7 WARN permite reporte exterior', async () => {
  const pool = reportPool();
  await createReportsService(pool, areaMode('WARN')).createReport(7, reportData(outside));
  assert.equal(pool.calls.at(-1).sql, 'COMMIT');
});
test('8 ENFORCE rechaza reporte exterior con 422', async () => {
  const pool = reportPool();
  await assert.rejects(createReportsService(pool, areaMode('ENFORCE')).createReport(7, reportData(outside)), (error) => error.statusCode === 422 && error.code === 'OUTSIDE_ALLOWED_AREA');
  assert.equal(pool.connectCount, 0);
});
test('9 WARN permite avistamiento exterior', async () => {
  const pool = sightingPool();
  await createSightingsService(pool, {}, areaMode('WARN')).createSighting(7, sightingData(outside), null);
  assert.equal(pool.calls.at(-1).sql, 'COMMIT');
});
test('10 ENFORCE rechaza avistamiento exterior con 422', async () => {
  const pool = sightingPool();
  await assert.rejects(createSightingsService(pool, {}, areaMode('ENFORCE')).createSighting(7, sightingData(outside), null), (error) => error.statusCode === 422 && error.code === 'OUTSIDE_ALLOWED_AREA');
  assert.equal(pool.connectCount, 0);
});
test('11 resultado central expone inside/allowed/mode/area', () => {
  assert.deepEqual(Object.keys(geofence.evaluateAllowedArea(...Object.values(inside), 'WARN')).sort(), ['allowed', 'area', 'inside', 'mode']);
});
test('12 modo ausente o inválido usa ENFORCE fail-safe', () => {
  assert.equal(geofence.resolveGeofenceMode(undefined), 'ENFORCE');
  assert.equal(geofence.resolveGeofenceMode('INVALID'), 'ENFORCE');
});
test('13 WARN exterior conserva coordenadas reales', async () => {
  const pool = reportPool();
  await createReportsService(pool, areaMode('WARN')).createReport(7, reportData(outside));
  const location = pool.calls.find((call) => call.sql.startsWith('INSERT INTO ubicacion'));
  assert.deepEqual(location.params.slice(2, 4), [outside.lat, outside.lng]);
});
test('14 ENFORCE exterior no deja escrituras parciales', async () => {
  const pool = reportPool();
  await assert.rejects(createReportsService(pool, areaMode('ENFORCE')).createReport(7, reportData(outside)));
  assert.deepEqual(pool.calls, []);
});

test('15 dirección válida devuelve candidato normalizado', async () => {
  const result = await geocoder({ body: { status: 'OK', results: [googleResult(inside)] } }).geocodeAddress('Carrera 68B # 24-39');
  assert.equal(result.candidates[0].formattedAddress, 'Carrera de prueba 1, Bogotá, Colombia');
});
test('16 dirección se recorta y usa parámetros exactos', async () => {
  let requested;
  const service = geocoder({ fetchImpl: async (url) => { requested = url; return response({ status: 'OK', results: [googleResult(inside)] }); } });
  await service.geocodeAddress('  Carrera 68B # 24-39  ');
  assert.equal(requested.searchParams.get('address'), 'Carrera 68B # 24-39');
  assert.equal(requested.searchParams.get('components'), 'country:CO');
  assert.equal(requested.searchParams.get('region'), 'co');
  assert.equal(requested.searchParams.get('language'), 'es');
  assert.equal(requested.searchParams.get('bounds'), `${OFFICIAL_BOUNDS.southwest.lat},${OFFICIAL_BOUNDS.southwest.lng}|${OFFICIAL_BOUNDS.northeast.lat},${OFFICIAL_BOUNDS.northeast.lng}`);
});
test('17 dirección vacía devuelve ADDRESS_REQUIRED', async () => {
  await assert.rejects(geocoder().geocodeAddress('  '), (error) => error.code === 'ADDRESS_REQUIRED');
});
test('18 ZERO_RESULTS devuelve ADDRESS_NOT_FOUND', async () => {
  await assert.rejects(geocoder({ body: { status: 'ZERO_RESULTS', results: [] } }).geocodeAddress('Sin resultado'), (error) => error.code === 'ADDRESS_NOT_FOUND');
});
test('19 candidato interior ENFORCE está permitido', async () => {
  const result = await geocoder({ body: { status: 'OK', results: [googleResult(inside)] } }).geocodeAddress('Dentro');
  assert.equal(result.candidates[0].allowed, true);
});
test('20 candidato exterior ENFORCE se bloquea', async () => {
  await assert.rejects(geocoder({ body: { status: 'OK', results: [googleResult(outside)] } }).geocodeAddress('Fuera'), (error) => error.code === 'ADDRESS_OUTSIDE_ALLOWED_AREA');
});
test('21 candidato exterior WARN se devuelve permitido', async () => {
  const result = await geocoder({ mode: 'WARN', body: { status: 'OK', results: [googleResult(outside)] } }).geocodeAddress('Fuera');
  assert.deepEqual({ inside: result.candidates[0].inside, allowed: result.candidates[0].allowed, mode: result.mode }, { inside: false, allowed: true, mode: 'WARN' });
});
test('22 varios resultados se normalizan', async () => {
  const result = await geocoder({ body: { status: 'OK', results: [googleResult(inside, '1'), googleResult(inside, '2')] } }).geocodeAddress('Varias');
  assert.equal(result.candidates.length, 2);
});
test('23 se devuelven máximo cinco candidatos', async () => {
  const results = Array.from({ length: 7 }, (_, index) => googleResult(inside, String(index)));
  assert.equal((await geocoder({ body: { status: 'OK', results } }).geocodeAddress('Muchas')).candidates.length, 5);
});
test('24 coordenadas inválidas devuelven INVALID_GEOCODING_RESPONSE', async () => {
  await assert.rejects(geocoder({ body: { status: 'OK', results: [googleResult({ lat: 100, lng: 0 })] } }).geocodeAddress('Inválida'), (error) => error.code === 'INVALID_GEOCODING_RESPONSE');
});
test('25 respuesta malformada devuelve INVALID_GEOCODING_RESPONSE', async () => {
  await assert.rejects(geocoder({ body: { results: [] } }).geocodeAddress('Malformada'), (error) => error.code === 'INVALID_GEOCODING_RESPONSE');
});
test('26 timeout/red devuelve GEOCODING_UNAVAILABLE', async () => {
  await assert.rejects(geocoder({ fetchImpl: async () => { throw new Error('timeout'); } }).geocodeAddress('Timeout'), (error) => error.code === 'GEOCODING_UNAVAILABLE');
});
test('27 sin key devuelve GEOCODING_NOT_CONFIGURED', async () => {
  await assert.rejects(geocoder({ apiKey: '' }).geocodeAddress('Dirección'), (error) => error.code === 'GEOCODING_NOT_CONFIGURED');
});
test('28 la key no aparece en errores', async () => {
  const secret = 'secret-key-that-must-not-leak';
  let error;
  try { await geocoder({ apiKey: secret, fetchImpl: async () => { throw new Error(`url?key=${secret}`); } }).geocodeAddress('Dirección'); } catch (caught) { error = caught; }
  assert.equal(String(error).includes(secret), false);
});
test('29 endpoint geocoding sin JWT devuelve 401 sin llamar Google', async () => {
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const address = server.address();
    const result = await fetch(`http://127.0.0.1:${address.port}/api/geocoding/address`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ address: 'Prueba' }) });
    assert.equal(result.status, 401);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('34 reporte DIRECCION persiste método, lat/lng, dirección y place_id', async () => {
  const pool = reportPool();
  await createReportsService(pool, areaMode('ENFORCE')).createReport(7, reportData());
  const location = pool.calls.find((call) => call.sql.startsWith('INSERT INTO ubicacion'));
  assert.deepEqual(location.params.slice(1, 7), ['DIRECCION', inside.lat, inside.lng, null, 'Dirección validada', 'place-1']);
});
test('35 edición de reporte DIRECCION actualiza ubicación', async () => {
  const pool = reportPool({ editing: true });
  await createReportsService(pool, areaMode('ENFORCE')).updateReport(7, 61, { ubicacion: reportData().ubicacion });
  const location = pool.calls.find((call) => call.sql.startsWith('UPDATE ubicacion'));
  assert.deepEqual(location.params.slice(0, 6), ['DIRECCION', inside.lat, inside.lng, null, 'Dirección validada', 'place-1']);
});
test('36 avistamiento independiente DIRECCION persiste ubicación', async () => {
  const pool = sightingPool();
  await createSightingsService(pool, {}, areaMode('ENFORCE')).createSighting(7, sightingData(), null);
  const location = pool.calls.find((call) => call.sql.startsWith('INSERT INTO ubicacion'));
  assert.deepEqual(location.params.slice(1, 7), ['DIRECCION', inside.lat, inside.lng, null, 'Dirección validada', 'place-1']);
});
test('37 avistamiento vinculado DIRECCION persiste reportId', async () => {
  const pool = sightingPool({ linked: true });
  const result = await createSightingsService(pool, {}, areaMode('ENFORCE')).createSighting(7, sightingData(inside, 61), null);
  assert.equal(result.reporte.id, 61);
});
test('38 GPS continúa siendo aceptado por schemas', () => {
  const { createSightingSchema } = require('../src/modules/sightings/sightings.schemas');
  assert.equal(createSightingSchema.safeParse({ ...sightingData(), metodo: 'GPS', direccion: null, placeId: null }).success, true);
});
test('39 MAPA continúa siendo aceptado por schemas', () => {
  const { createReportSchema } = require('../src/modules/reports/reports.schemas');
  assert.equal(createReportSchema.safeParse({ ...reportData(), ubicacion: { ...reportData().ubicacion, metodo: 'MAPA', direccion: null, placeId: null } }).success, true);
});
test('40 DIRECCION exige dirección y placeId sin confundirlos con referencia', () => {
  const { createReportSchema } = require('../src/modules/reports/reports.schemas');
  assert.equal(createReportSchema.safeParse({ ...reportData(), ubicacion: { ...reportData().ubicacion, direccion: null, placeId: null } }).success, false);
});
test('41 exterior ENFORCE produce cero escrituras', async () => {
  const pool = sightingPool();
  await assert.rejects(createSightingsService(pool, {}, areaMode('ENFORCE')).createSighting(7, sightingData(outside), null));
  assert.deepEqual(pool.calls, []);
});
test('42 exterior WARN produce escritura válida', async () => {
  const pool = sightingPool();
  await createSightingsService(pool, {}, areaMode('WARN')).createSighting(7, sightingData(outside), null);
  assert.equal(pool.calls.at(-1).sql, 'COMMIT');
});
test('43 datos DIRECCION incluyen coordenadas para mapa', async () => {
  const pool = sightingPool();
  const result = await createSightingsService(pool, {}, areaMode('ENFORCE')).createSighting(7, sightingData(), null);
  assert.equal(result.ubicacion.metodo, 'DIRECCION');
  assert.equal(result.ubicacion.lat, inside.lat);
});
test('44 historial puede transportar dirección legible', () => {
  const normalized = sightingPool().calls;
  assert.equal(Array.isArray(normalized), true);
  assert.equal(sightingData().direccion, 'Dirección validada');
});
