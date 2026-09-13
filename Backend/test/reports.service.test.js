const test = require('node:test');
const assert = require('node:assert/strict');
const { createReportsService } = require('../src/modules/reports/reports.service');

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
  return {
    calls,
    connect: async () => client,
    query: client.query,
  };
}

const location = {
  metodo: 'MAPA',
  lat: 4.6569,
  lng: -74.1095,
  precisionM: null,
  direccion: 'Punto seleccionado',
  placeId: null,
};

test('lista mascotas reportables filtrando por el usuario autenticado', async () => {
  const pool = fakePool((sql, params) => {
    assert.ok(sql.includes('WHERE m.fk_usuario = $1'));
    assert.deepEqual(params, [3]);
    return {
      rowCount: 1,
      rows: [{
        id: 7,
        nombre: 'Temporal',
        especie: 'Perro',
        raza: 'Criollo',
        estado: 'ACTIVA',
        tiene_reporte_activo: false,
        foto_storage_ref: 'foto-temporal',
        foto_url_preview: null,
      }],
    };
  });
  const service = createReportsService(pool);

  const pets = await service.listReportablePets(3);

  assert.equal(pets.length, 1);
  assert.equal(pets[0].id, 7);
  assert.equal(pets[0].fotoPrincipal.id, 'foto-temporal');
});

test('crea reporte y marca la mascota como PERDIDA en una transacción', async () => {
  const pool = fakePool((sql) => {
    if (sql.startsWith('SELECT id, estado FROM mascota')) {
      return { rowCount: 1, rows: [{ id: 7, estado: 'ACTIVA' }] };
    }
    if (sql.startsWith('SELECT id FROM reporte')) {
      return { rowCount: 0, rows: [] };
    }
    if (sql.startsWith('INSERT INTO reporte')) {
      return {
        rowCount: 1,
        rows: [{ id: 11, estado: 'ACTIVO', creado_en: new Date() }],
      };
    }
    return { rowCount: 1, rows: [] };
  });
  const service = createReportsService(pool);

  const report = await service.createReport(3, {
    mascotaId: 7,
    descripcion: 'Se perdió cerca del parque',
    mostrarContacto: false,
    ubicacion: location,
  });

  assert.equal(report.id, 11);
  assert.ok(pool.calls.some((call) => call.sql === 'BEGIN'));
  assert.ok(pool.calls.some((call) => call.sql.includes("estado = 'PERDIDA'")));
  assert.equal(pool.calls.at(-1).sql, 'COMMIT');
});

test('rechaza una mascota ajena o inactiva antes de insertar', async () => {
  const pool = fakePool((sql) => {
    if (sql.startsWith('SELECT id, estado FROM mascota')) {
      return { rowCount: 0, rows: [] };
    }
    throw new Error(`Consulta inesperada: ${sql}`);
  });
  const service = createReportsService(pool);

  await assert.rejects(
    service.createReport(3, {
      mascotaId: 99,
      descripcion: null,
      mostrarContacto: false,
      ubicacion: location,
    }),
    (error) => error.statusCode === 404
  );
  assert.equal(pool.calls.at(-1).sql, 'ROLLBACK');
});

test('impide crear un segundo reporte activo', async () => {
  const pool = fakePool((sql) => {
    if (sql.startsWith('SELECT id, estado FROM mascota')) {
      return { rowCount: 1, rows: [{ id: 7, estado: 'PERDIDA' }] };
    }
    if (sql.startsWith('SELECT id FROM reporte')) {
      return { rowCount: 1, rows: [{ id: 10 }] };
    }
    throw new Error(`Consulta inesperada: ${sql}`);
  });
  const service = createReportsService(pool);

  await assert.rejects(
    service.createReport(3, {
      mascotaId: 7,
      descripcion: null,
      mostrarContacto: false,
      ubicacion: location,
    }),
    (error) => error.statusCode === 409
  );
  assert.equal(pool.calls.at(-1).sql, 'ROLLBACK');
});

test('finaliza el reporte y marca la mascota como ENCONTRADA', async () => {
  const pool = fakePool((sql) => {
    if (sql.startsWith('SELECT id, fk_mascota, estado FROM reporte')) {
      return {
        rowCount: 1,
        rows: [{ id: 11, fk_mascota: 7, estado: 'ACTIVO' }],
      };
    }
    return { rowCount: 1, rows: [{ id: 7 }] };
  });
  const service = createReportsService(pool);

  const report = await service.closeReport(3, 11);

  assert.equal(report.estado, 'FINALIZADO');
  assert.ok(pool.calls.some((call) => call.sql.includes("estado = 'FINALIZADO'")));
  assert.ok(pool.calls.some((call) => call.sql.includes("estado = 'ENCONTRADA'")));
  assert.equal(pool.calls.at(-1).sql, 'COMMIT');
});

test('no permite volver a cerrar un reporte finalizado', async () => {
  const pool = fakePool((sql) => {
    if (sql.startsWith('SELECT id, fk_mascota, estado FROM reporte')) {
      return {
        rowCount: 1,
        rows: [{ id: 11, fk_mascota: 7, estado: 'FINALIZADO' }],
      };
    }
    throw new Error(`Consulta inesperada: ${sql}`);
  });
  const service = createReportsService(pool);

  await assert.rejects(
    service.closeReport(3, 11),
    (error) => error.statusCode === 409
  );
  assert.equal(pool.calls.at(-1).sql, 'ROLLBACK');
});

test('no permite editar un reporte finalizado', async () => {
  const pool = fakePool((sql) => {
    if (sql.startsWith('SELECT id, descripcion, mostrar_contacto, estado')) {
      return {
        rowCount: 1,
        rows: [{
          id: 11,
          descripcion: 'Original',
          mostrar_contacto: false,
          estado: 'FINALIZADO',
        }],
      };
    }
    throw new Error(`Consulta inesperada: ${sql}`);
  });
  const service = createReportsService(pool);

  await assert.rejects(
    service.updateReport(3, 11, { descripcion: 'Cambio' }),
    (error) => error.statusCode === 409
  );
  assert.equal(pool.calls.at(-1).sql, 'ROLLBACK');
});

test('edita un reporte activo y su ubicación en una transacción', async () => {
  const pool = fakePool((sql) => {
    if (sql.startsWith('SELECT id, descripcion, mostrar_contacto, estado')) {
      return {
        rowCount: 1,
        rows: [{
          id: 11,
          descripcion: 'Original',
          mostrar_contacto: false,
          estado: 'ACTIVO',
        }],
      };
    }
    if (sql.startsWith('UPDATE ubicacion')) {
      return { rowCount: 1, rows: [] };
    }
    return { rowCount: 1, rows: [] };
  });
  const service = createReportsService(pool);

  const report = await service.updateReport(3, 11, {
    descripcion: 'Actualizado',
    mostrarContacto: true,
    ubicacion: location,
  });

  assert.equal(report.estado, 'ACTIVO');
  assert.ok(pool.calls.some(
    (call) =>
      call.sql.startsWith('UPDATE reporte') &&
      call.sql.includes("AT TIME ZONE 'America/Bogota'")
  ));
  assert.ok(pool.calls.some((call) => call.sql.startsWith('UPDATE ubicacion')));
  assert.equal(pool.calls.at(-1).sql, 'COMMIT');
});
