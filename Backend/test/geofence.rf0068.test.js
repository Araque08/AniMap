const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');

const app = require('../src/app');
const { signAccessToken } = require('../src/utils/jwt');
const geofence = require('../src/modules/geofence/geofence.service');
const { createReportsService } = require('../src/modules/reports/reports.service');
const { createSightingsService } = require('../src/modules/sightings/sightings.service');

const inside = { lat: 4.651, lng: -74.109 };
const outside = { lat: 4.65, lng: -74.1 };

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

function successfulReportPool({ editing = false } = {}) {
  return fakePool((sql) => {
    if (editing && sql.startsWith('SELECT id, descripcion')) {
      return {
        rowCount: 1,
        rows: [{ id: 61, descripcion: 'Antes', mostrar_contacto: false, estado: 'ACTIVO' }],
      };
    }
    if (editing && sql.startsWith('UPDATE reporte')) {
      return { rowCount: 1, rows: [{ actualizado_en: '2026-09-13T12:00:00-05:00' }] };
    }
    if (editing && sql.startsWith('UPDATE ubicacion')) {
      return { rowCount: 1, rows: [] };
    }
    if (sql.startsWith('SELECT id, estado')) {
      return { rowCount: 1, rows: [{ id: 31, estado: 'ACTIVA' }] };
    }
    if (sql.startsWith('SELECT id FROM reporte')) return { rowCount: 0, rows: [] };
    if (sql.startsWith('INSERT INTO reporte')) {
      return { rowCount: 1, rows: [{ id: 61, estado: 'ACTIVO' }] };
    }
    return { rowCount: 1, rows: [] };
  });
}

function reportData(position) {
  return {
    mascotaId: 31,
    descripcion: 'Reporte temporal',
    mostrarContacto: false,
    ubicacion: {
      metodo: 'MAPA',
      lat: position.lat,
      lng: position.lng,
      precisionM: null,
      direccion: null,
      placeId: null,
    },
  };
}

function successfulSightingPool({ linked = false, photo = null } = {}) {
  return fakePool((sql) => {
    if (sql.startsWith('SELECT r.id, r.estado')) {
      return {
        rowCount: 1,
        rows: [{ id: 61, estado: 'ACTIVO', mascota_estado: 'PERDIDA' }],
      };
    }
    if (sql.startsWith('INSERT INTO avistamiento')) {
      return { rowCount: 1, rows: [{ id: 91 }] };
    }
    if (sql.startsWith('SELECT a.id')) {
      return {
        rowCount: 1,
        rows: [{
          id: 91,
          descripcion: 'Visto en la zona',
          fk_reporte_perdida: linked ? 61 : null,
          fecha_hora: '2026-09-13T17:00:00.000Z',
          metodo: 'MAPA',
          lat: String(inside.lat),
          lng: String(inside.lng),
          precision_m: null,
          storage_ref: photo,
          url_preview: photo ? `/api/sightings/images/${photo}` : null,
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

function sightingData(position, reportId = null) {
  return {
    descripcion: 'Visto en la zona',
    reportId,
    metodo: 'MAPA',
    lat: position.lat,
    lng: position.lng,
    precisionM: null,
  };
}

async function checkApi(body, authenticated = true) {
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const address = server.address();
    const headers = { 'Content-Type': 'application/json' };
    if (authenticated) {
      headers.Authorization = `Bearer ${signAccessToken({ sub: '7', deviceId: 'geofence-test' })}`;
    }
    return await fetch(`http://127.0.0.1:${address.port}/api/geofence/check`, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('1 carga del GeoJSON oficial', () => {
  assert.equal(geofence.officialFeature.type, 'Feature');
  assert.ok(geofence.officialFeature.geometry.coordinates.length > 0);
});

test('2 código oficial 006313 correcto', () => {
  assert.equal(geofence.officialFeature.properties.SCACODIGO, '006313');
});

test('3 nombre oficial Salitre Occidental correcto', () => {
  assert.equal(geofence.officialFeature.properties.SCANOMBRE, 'SALITRE OCCIDENTAL');
  assert.equal(geofence.area.name, 'Salitre Occidental');
});

test('4 Polygon y MultiPolygon, incluidos huecos, están soportados', () => {
  const polygon = {
    type: 'Polygon',
    coordinates: [
      [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
      [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]],
    ],
  };
  const multi = { type: 'MultiPolygon', coordinates: [polygon.coordinates] };
  assert.equal(geofence.geometryContains(polygon, [2, 2]), true);
  assert.equal(geofence.geometryContains(polygon, [5, 5]), false);
  assert.equal(geofence.geometryContains(multi, [2, 2]), true);
});

test('5 punto claramente interior devuelve true', () => {
  assert.equal(geofence.isInsideAllowedArea(inside.lat, inside.lng), true);
});

test('6 punto claramente exterior devuelve false', () => {
  assert.equal(geofence.isInsideAllowedArea(outside.lat, outside.lng), false);
});

test('7 punto exactamente sobre segmento devuelve true', () => {
  const ring = geofence.officialFeature.geometry.coordinates[0];
  const midpoint = [(ring[0][0] + ring[1][0]) / 2, (ring[0][1] + ring[1][1]) / 2];
  assert.equal(geofence.isInsideAllowedArea(midpoint[1], midpoint[0]), true);
});

test('8 punto exactamente sobre vértice devuelve true', () => {
  const vertex = geofence.officialFeature.geometry.coordinates[0][0];
  assert.equal(geofence.isInsideAllowedArea(vertex[1], vertex[0]), true);
});

test('9 latitud inválida se rechaza', () => {
  assert.throws(() => geofence.isInsideAllowedArea(91, inside.lng), /latitud/);
});

test('10 longitud inválida se rechaza', () => {
  assert.throws(() => geofence.isInsideAllowedArea(inside.lat, -181), /longitud/);
});

test('11 latitud y longitud invertidas no se aceptan por accidente', () => {
  assert.equal(geofence.isInsideAllowedArea(inside.lng, inside.lat), false);
});

test('12 API check interior devuelve true y área pública mínima', async () => {
  const response = await checkApi(inside);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    inside: true,
    allowed: true,
    mode: geofence.resolveGeofenceMode(),
    area: { code: '006313', name: 'Salitre Occidental' },
  });
});

test('13 API check exterior devuelve false', async () => {
  const response = await checkApi(outside);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).inside, false);
});

test('14 API check sin JWT se rechaza', async () => {
  const response = await checkApi(inside, false);
  assert.equal(response.status, 401);
});

test('15 API check con body inválido se rechaza controladamente', async () => {
  const response = await checkApi({ lat: 1000, lng: 'no-numero' });
  assert.equal(response.status, 400);
  assert.equal((await response.json()).ok, false);
});

test('16 crear reporte interior está permitido', async () => {
  const pool = successfulReportPool();
  const result = await createReportsService(pool).createReport(7, reportData(inside));
  assert.equal(result.estado, 'ACTIVO');
  assert.equal(pool.calls.at(-1).sql, 'COMMIT');
});

test('17 crear reporte exterior devuelve OUTSIDE_ALLOWED_AREA', async () => {
  const pool = successfulReportPool();
  await assert.rejects(
    createReportsService(pool).createReport(7, reportData(outside)),
    (error) => error.statusCode === 422 && error.code === 'OUTSIDE_ALLOWED_AREA',
  );
});

test('18 reporte exterior no inicia transacción ni escribe', async () => {
  const pool = successfulReportPool();
  await assert.rejects(createReportsService(pool).createReport(7, reportData(outside)));
  assert.equal(pool.connectCount, 0);
  assert.deepEqual(pool.calls, []);
});

test('19 editar ubicación interior está permitido', async () => {
  const pool = successfulReportPool({ editing: true });
  await createReportsService(pool).updateReport(7, 61, {
    descripcion: 'Actualizado',
    ubicacion: reportData(inside).ubicacion,
  });
  assert.ok(pool.calls.some((call) => call.sql.startsWith('UPDATE ubicacion')));
  assert.equal(pool.calls.at(-1).sql, 'COMMIT');
});

test('20 editar ubicación exterior se rechaza sin modificar la anterior', async () => {
  const pool = successfulReportPool({ editing: true });
  await assert.rejects(
    createReportsService(pool).updateReport(7, 61, {
      ubicacion: reportData(outside).ubicacion,
    }),
    (error) => error.code === 'OUTSIDE_ALLOWED_AREA',
  );
  assert.equal(pool.connectCount, 0);
  assert.deepEqual(pool.calls, []);
});

test('21 avistamiento independiente interior está permitido', async () => {
  const pool = successfulSightingPool();
  const result = await createSightingsService(pool, {}).createSighting(
    7,
    sightingData(inside),
    null,
  );
  assert.equal(result.vinculado, false);
  assert.equal(pool.calls.at(-1).sql, 'COMMIT');
});

test('22 avistamiento independiente exterior se rechaza', async () => {
  const pool = successfulSightingPool();
  await assert.rejects(
    createSightingsService(pool, {}).createSighting(7, sightingData(outside), null),
    (error) => error.code === 'OUTSIDE_ALLOWED_AREA',
  );
  assert.equal(pool.connectCount, 0);
});

test('23 avistamiento vinculado interior está permitido', async () => {
  const pool = successfulSightingPool({ linked: true });
  const result = await createSightingsService(pool, {}).createSighting(
    7,
    sightingData(inside, 61),
    null,
  );
  assert.equal(result.vinculado, true);
});

test('24 avistamiento vinculado exterior se rechaza', async () => {
  const pool = successfulSightingPool({ linked: true });
  await assert.rejects(
    createSightingsService(pool, {}).createSighting(7, sightingData(outside, 61), null),
    (error) => error.code === 'OUTSIDE_ALLOWED_AREA',
  );
  assert.equal(pool.connectCount, 0);
});

test('25 exterior con foto deja cero residuos PostgreSQL y Mongo', async () => {
  const pool = successfulSightingPool();
  let mongoWrites = 0;
  const images = {
    async saveSightingImage() { mongoWrites += 1; },
    async deleteSightingImage() { assert.fail('No existe imagen que compensar'); },
  };
  await assert.rejects(
    createSightingsService(pool, images).createSighting(
      7,
      sightingData(outside),
      { buffer: Buffer.from([1]) },
    ),
  );
  assert.equal(pool.connectCount, 0);
  assert.equal(pool.calls.length, 0);
  assert.equal(mongoWrites, 0);
});
