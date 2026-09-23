const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');

const app = require('../src/app');
const { signAccessToken } = require('../src/utils/jwt');
const { createSightingSchema } = require('../src/modules/sightings/sightings.schemas');
const { createSightingsService } = require('../src/modules/sightings/sightings.service');

function fakePool(handler) {
  const calls = [];
  const client = {
    async query(sql, params) {
      const normalized = sql.trim().replace(/\s+/g, ' ');
      calls.push({ sql: normalized, params });
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(normalized)) {
        return { rowCount: 0, rows: [] };
      }
      return handler(normalized, params, calls);
    },
    release() {},
  };
  return { calls, connect: async () => client, query: client.query };
}

function sightingRow({ reportId = null, storageRef = null } = {}) {
  return {
    id: 41,
    descripcion: 'Perro café visto cerca del parque',
    fk_reporte_perdida: reportId,
    fecha_hora: '2026-09-13T15:00:00.000Z',
    metodo: 'GPS',
    lat: '4.651',
    lng: '-74.109',
    precision_m: '8.5',
    storage_ref: storageRef,
    url_preview: storageRef ? `/api/sightings/images/${storageRef}` : null,
    reporte_id: reportId,
    mascota_nombre: reportId ? 'Luna' : null,
    especie_nombre: reportId ? 'Perro' : null,
    raza_nombre: reportId ? 'Criollo' : null,
  };
}

const gpsData = {
  descripcion: 'Perro café visto cerca del parque',
  reportId: null,
  metodo: 'GPS',
  lat: 4.651,
  lng: -74.109,
  precisionM: 8.5,
};

function successfulPool({ reportId = null, storageRef = null } = {}) {
  return fakePool((sql) => {
    if (sql.startsWith('SELECT r.id, r.estado')) {
      return {
        rowCount: 1,
        rows: [{ id: reportId, estado: 'ACTIVO', mascota_estado: 'PERDIDA' }],
      };
    }
    if (sql.startsWith('INSERT INTO avistamiento')) {
      return { rowCount: 1, rows: [{ id: 41 }] };
    }
    if (sql.startsWith('SELECT a.id')) {
      return { rowCount: 1, rows: [sightingRow({ reportId, storageRef })] };
    }
    return { rowCount: 1, rows: [] };
  });
}

test('1 independiente sin foto se crea transaccionalmente y estado queda NULL', async () => {
  const pool = successfulPool();
  const images = { saveSightingImage: async () => assert.fail('Mongo no debe usarse') };
  const service = createSightingsService(pool, images);

  const result = await service.createSighting(7, gpsData, null);

  assert.equal(result.vinculado, false);
  const insert = pool.calls.find((call) => call.sql.startsWith('INSERT INTO avistamiento'));
  assert.deepEqual(insert.params, [7, null, gpsData.descripcion]);
  assert.match(insert.sql, /estado \) VALUES .* NULL\)/);
  assert.equal(pool.calls.at(-1).sql, 'COMMIT');
});

test('2 independiente con una foto persiste Mongo y referencia PostgreSQL', async () => {
  const storageRef = '64b7f2d1258f4f3aa1234567';
  const pool = successfulPool({ storageRef });
  let saved = 0;
  const images = {
    saveSightingImage: async ({ sightingId, userId }) => {
      saved += 1;
      assert.equal(sightingId, 41);
      assert.equal(userId, 7);
      return { storageRef, urlPreview: `/api/sightings/images/${storageRef}` };
    },
    deleteSightingImage: async () => assert.fail('No debe compensar un éxito'),
  };
  const service = createSightingsService(pool, images);

  const result = await service.createSighting(7, gpsData, { buffer: Buffer.from([1]) });

  assert.equal(saved, 1);
  assert.equal(result.foto.id, storageRef);
  assert.ok(pool.calls.some((call) => call.sql.startsWith('INSERT INTO foto_avistamiento')));
  assert.equal(pool.calls.at(-1).sql, 'COMMIT');
});

test('3 cualquier usuario autenticado puede vincularse a un reporte ACTIVO', async () => {
  const pool = successfulPool({ reportId: 88 });
  const service = createSightingsService(pool, {});

  const result = await service.createSighting(7, { ...gpsData, reportId: 88 }, null);

  const lookup = pool.calls.find((call) => call.sql.startsWith('SELECT r.id, r.estado'));
  assert.deepEqual(lookup.params, [88]);
  assert.ok(!lookup.sql.includes('fk_usuario'));
  assert.equal(result.vinculado, true);
  assert.equal(result.reporte.id, 88);
});

test('4 reporte FINALIZADO se rechaza y revierte', async () => {
  const pool = fakePool((sql) => {
    if (sql.startsWith('SELECT r.id, r.estado')) {
      return { rowCount: 1, rows: [{ id: 88, estado: 'FINALIZADO', mascota_estado: 'ACTIVA' }] };
    }
    throw new Error(`Consulta inesperada: ${sql}`);
  });
  const service = createSightingsService(pool, {});

  await assert.rejects(
    service.createSighting(7, { ...gpsData, reportId: 88 }, null),
    (error) => error.statusCode === 409 && /ya no está activo/.test(error.message),
  );
  assert.equal(pool.calls.at(-1).sql, 'ROLLBACK');
});

test('5 reporte inexistente se rechaza y revierte', async () => {
  const pool = fakePool((sql) => {
    if (sql.startsWith('SELECT r.id, r.estado')) return { rowCount: 0, rows: [] };
    throw new Error(`Consulta inesperada: ${sql}`);
  });
  const service = createSightingsService(pool, {});

  await assert.rejects(
    service.createSighting(7, { ...gpsData, reportId: 999 }, null),
    (error) => error.statusCode === 404 && /no existe/.test(error.message),
  );
  assert.equal(pool.calls.at(-1).sql, 'ROLLBACK');
});

test('6 descripción vacía es inválida', () => {
  const result = createSightingSchema.safeParse({ ...gpsData, descripcion: '   ' });
  assert.equal(result.success, false);
  assert.match(result.error.issues[0].message, /obligatoria/);
});

test('7 GPS válido conserva precisión', () => {
  const result = createSightingSchema.parse(gpsData);
  assert.equal(result.metodo, 'GPS');
  assert.equal(result.precisionM, 8.5);
});

test('8 MAPA válido permite precisión nula', () => {
  const result = createSightingSchema.parse({
    ...gpsData,
    metodo: 'MAPA',
    precisionM: '',
  });
  assert.equal(result.metodo, 'MAPA');
  assert.equal(result.precisionM, null);
});

test('9 coordenadas fuera de rango son inválidas', () => {
  assert.equal(createSightingSchema.safeParse({ ...gpsData, lat: 91 }).success, false);
  assert.equal(createSightingSchema.safeParse({ ...gpsData, lng: -181 }).success, false);
});

test('10 DIRECCION exige coordenadas, dirección y placeId validados', () => {
  const result = createSightingSchema.safeParse({ ...gpsData, metodo: 'DIRECCION' });
  assert.equal(result.success, false);
  assert.match(result.error.issues[0].message, /dirección validada/i);
  assert.equal(createSightingSchema.safeParse({
    ...gpsData,
    metodo: 'DIRECCION',
    direccion: 'Carrera 68B # 24-39, Bogotá',
    placeId: 'place-validado',
  }).success, true);
});

async function requestValidation(form, authenticated = true) {
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const address = server.address();
    const headers = authenticated
      ? { Authorization: `Bearer ${signAccessToken({ sub: '7', deviceId: 'phase1a-test' })}` }
      : {};
    return await fetch(`http://127.0.0.1:${address.port}/api/sightings`, {
      method: 'POST',
      headers,
      body: form,
    });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function validForm() {
  const form = new FormData();
  form.append('descripcion', 'Avistamiento temporal');
  form.append('metodo', 'MAPA');
  form.append('lat', '4.6569');
  form.append('lng', '-74.1095');
  return form;
}

test('11 foto mayor a 5 MB se rechaza antes del servicio', async () => {
  const form = validForm();
  const bytes = new Uint8Array(5 * 1024 * 1024 + 1);
  bytes.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  form.append('foto', new Blob([bytes], { type: 'image/png' }), 'grande.png');
  const response = await requestValidation(form);
  assert.equal(response.status, 400);
  assert.match((await response.json()).message, /máximo 5 MB/);
});

test('12 MIME o firma inválidos se rechazan', async () => {
  const form = validForm();
  form.append('foto', new Blob([Uint8Array.from([1, 2, 3])], { type: 'text/plain' }), 'falsa.jpg');
  const response = await requestValidation(form);
  assert.equal(response.status, 400);
  assert.match((await response.json()).message, /imagen JPG/);
});

test('13 fallo Mongo revierte PostgreSQL sin insertar foto', async () => {
  const pool = successfulPool();
  const images = {
    saveSightingImage: async () => { throw new Error('Mongo temporalmente no disponible'); },
  };
  const service = createSightingsService(pool, images);
  await assert.rejects(service.createSighting(7, gpsData, { buffer: Buffer.from([1]) }));
  assert.equal(pool.calls.at(-1).sql, 'ROLLBACK');
  assert.ok(!pool.calls.some((call) => call.sql.startsWith('INSERT INTO foto_avistamiento')));
});

test('14 fallo PostgreSQL posterior a Mongo elimina la imagen compensatoriamente', async () => {
  const storageRef = '64b7f2d1258f4f3aa1234567';
  const pool = fakePool((sql) => {
    if (sql.startsWith('INSERT INTO avistamiento')) return { rowCount: 1, rows: [{ id: 41 }] };
    if (sql.startsWith('INSERT INTO foto_avistamiento')) throw new Error('Fallo PG simulado');
    return { rowCount: 1, rows: [] };
  });
  const deleted = [];
  const images = {
    saveSightingImage: async () => ({ storageRef, urlPreview: `/api/sightings/images/${storageRef}` }),
    deleteSightingImage: async (id) => deleted.push(id),
  };
  const service = createSightingsService(pool, images);
  await assert.rejects(service.createSighting(7, gpsData, { buffer: Buffer.from([1]) }));
  assert.deepEqual(deleted, [storageRef]);
  assert.equal(pool.calls.at(-1).sql, 'ROLLBACK');
});

test('15 usuario no autenticado recibe 401 antes de procesar multipart', async () => {
  const response = await requestValidation(validForm(), false);
  assert.equal(response.status, 401);
  assert.equal((await response.json()).code, 'ACCESS_TOKEN_REQUIRED');
});

test('16 detalle público no expone nombre, email, teléfono ni userId', async () => {
  const pool = fakePool((sql) => {
    if (sql.startsWith('SELECT a.id')) {
      return { rowCount: 1, rows: [sightingRow({ reportId: 88 })] };
    }
    throw new Error(`Consulta inesperada: ${sql}`);
  });
  const service = createSightingsService(pool, {});
  const sighting = await service.getPublicSighting(41);
  const serialized = JSON.stringify(sighting);
  assert.ok(!serialized.includes('reporter'));
  assert.ok(!serialized.includes('email'));
  assert.ok(!serialized.includes('telefono'));
  assert.ok(!serialized.includes('userId'));
});

test('el esquema no acepta userId enviado por el cliente', () => {
  const result = createSightingSchema.safeParse({ ...gpsData, userId: 99 });
  assert.equal(result.success, false);
  assert.equal(result.error.issues[0].code, 'unrecognized_keys');
});
