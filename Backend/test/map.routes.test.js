const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const express = require('express');

const postgres = require('../src/config/postgres_db');
const mapRoutes = require('../src/modules/map/map.routes');

function reportRow({ id, mostrarContacto, ownerId = id }) {
  return {
    reporte_id: id,
    reporte_descripcion: 'Reporte temporal',
    reporte_estado: 'ACTIVO',
    creado_en: new Date('2026-09-12T12:00:00.000Z'),
    cerrado_en: null,
    mostrar_contacto: mostrarContacto,
    report_owner_id: ownerId,
    mascota_id: id,
    mascota_nombre: `Mascota ${id}`,
    mascota_color: 'Café',
    mascota_sexo: 'HEMBRA',
    mascota_estado: 'PERDIDA',
    especie_nombre: 'Perro',
    raza_nombre: 'Mestizo',
    owner_phone: '3000000000',
    lat: '4.6569',
    lng: '-74.1095',
    direccion: 'Ubicación de prueba',
    foto_storage_ref: null,
    foto_storage_refs: null,
  };
}

test('el mapa público solo expone el teléfono cuando fue autorizado', async (t) => {
  const originalQuery = postgres.query;
  postgres.query = async (sql) => {
    if (sql.includes('FROM reporte r')) {
      return {
        rows: [
          reportRow({ id: 1, mostrarContacto: false }),
          reportRow({ id: 2, mostrarContacto: true }),
        ],
      };
    }
    if (sql.includes('FROM avistamiento a')) {
      return {
        rows: [{
          avistamiento_id: 3,
          descripcion: 'Avistamiento existente',
          fecha_hora: new Date('2026-09-12T12:00:00.000Z'),
          estado: 'ACTIVO',
          lat: '4.65',
          lng: '-74.10',
          direccion: 'Ubicación existente',
          fk_reporte_perdida: null,
          foto_storage_ref: null,
          foto_url_preview: null,
        }],
      };
    }
    throw new Error('Consulta inesperada en la prueba');
  };

  const app = express();
  app.use('/api/map', mapRoutes);
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');

  t.after(async () => {
    postgres.query = originalQuery;
    await new Promise((resolve) => server.close(resolve));
  });

  const address = server.address();
  const response = await fetch(
    `http://127.0.0.1:${address.port}/api/map/reports`
  );
  const body = await response.json();

  assert.equal(response.status, 200);

  const hidden = body.data.find((item) => item.id === 'lost_1');
  assert.equal(body.data.filter((item) => item.id.startsWith('lost_')).length, 2);
  assert.equal(hidden.showContact, false);
  assert.equal(hidden.ownerPhone, '');
  assert.equal(hidden.ownerName, '');
  assert.equal(hidden.ownerEmail, '');

  const authorized = body.data.find((item) => item.id === 'lost_2');
  assert.equal(authorized.showContact, true);
  assert.equal(authorized.ownerPhone, '3000000000');
  assert.equal(authorized.ownerName, '');
  assert.equal(authorized.ownerEmail, '');
  assert.equal(authorized.location, 'Punto marcado en el mapa');
  assert.equal(authorized.reference, 'Ubicación de prueba');

  const sighting = body.data.find((item) => item.id === 'sighting_3');
  assert.equal(sighting.petName, 'Sin reporte vinculado');
  assert.equal(sighting.details, 'Avistamiento independiente');
  assert.equal('ownerName' in sighting, false);
  assert.equal('ownerPhone' in sighting, false);
  assert.equal('ownerEmail' in sighting, false);
});

test('el mapa publica todas las fotos con la principal primero', async (t) => {
  const originalQuery = postgres.query;
  postgres.query = async (sql) => {
    if (sql.includes('FROM reporte r')) {
      return {
        rows: [{
          ...reportRow({ id: 12, mostrarContacto: false }),
          foto_storage_ref: 'principal-id',
          foto_storage_refs: ['principal-id', 'secundaria-id'],
        }],
      };
    }
    if (sql.includes('FROM avistamiento a')) return { rows: [] };
    throw new Error('Consulta inesperada en la prueba');
  };

  const app = express();
  app.use('/api/map', mapRoutes);
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    postgres.query = originalQuery;
    await new Promise((resolve) => server.close(resolve));
  });

  const address = server.address();
  const response = await fetch(`http://127.0.0.1:${address.port}/api/map/reports`);
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.deepEqual(body.data[0].imageUrls, [
    '/api/map/images/principal-id',
    '/api/map/images/secundaria-id',
  ]);
  assert.equal(body.data[0].imageUrl, body.data[0].imageUrls[0]);
});

test('un reporte finalizado se publica como encontrado sin contacto', async (t) => {
  const originalQuery = postgres.query;
  postgres.query = async (sql) => {
    if (sql.includes('FROM reporte r')) {
      return {
        rows: [{
          ...reportRow({ id: 9, mostrarContacto: true, ownerId: 90 }),
          reporte_estado: 'FINALIZADO',
          mascota_estado: 'ACTIVA',
          cerrado_en: '2026-09-12T15:00:00.000-05:00',
        }],
      };
    }
    if (sql.includes('FROM avistamiento a')) return { rows: [] };
    throw new Error('Consulta inesperada en la prueba');
  };

  const app = express();
  app.use('/api/map', mapRoutes);
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    postgres.query = originalQuery;
    await new Promise((resolve) => server.close(resolve));
  });

  const address = server.address();
  const response = await fetch(`http://127.0.0.1:${address.port}/api/map/reports`);
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.data[0].type, 'found');
  assert.equal(body.data[0].dateText, '2026-09-12T15:00:00.000-05:00');
  assert.equal(body.data[0].showContact, false);
  assert.equal(body.data[0].ownerPhone, '');
});

test('un reporte propio se identifica sin exponer su teléfono', async (t) => {
  const originalQuery = postgres.query;
  postgres.query = async (sql) => {
    if (sql.includes('FROM reporte r')) {
      return {
        rows: [
          reportRow({ id: 7, mostrarContacto: true, ownerId: 42 }),
          reportRow({ id: 8, mostrarContacto: true, ownerId: 43 }),
        ],
      };
    }
    if (sql.includes('FROM avistamiento a')) return { rows: [] };
    throw new Error('Consulta inesperada en la prueba');
  };

  const { signAccessToken } = require('../src/utils/jwt');
  const app = express();
  app.use('/api/map', mapRoutes);
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');

  t.after(async () => {
    postgres.query = originalQuery;
    await new Promise((resolve) => server.close(resolve));
  });

  const address = server.address();
  const response = await fetch(
    `http://127.0.0.1:${address.port}/api/map/reports`,
    { headers: { Authorization: `Bearer ${signAccessToken({ sub: '42' })}` } }
  );
  const body = await response.json();
  const report = body.data.find((item) => item.id === 'lost_7');

  assert.equal(response.status, 200);
  assert.equal(report.isOwner, true);
  assert.equal(report.showContact, false);
  assert.equal(report.ownerPhone, '');
  assert.equal(Object.hasOwn(report, 'report_owner_id'), false);

  const otherReport = body.data.find((item) => item.id === 'lost_8');
  assert.equal(otherReport.isOwner, false);
  assert.equal(otherReport.showContact, true);
  assert.equal(otherReport.ownerPhone, '3000000000');
});

test('el mapa público limita solo FINALIZADOS usando cerrado_en y 30 días', async (t) => {
  const originalQuery = postgres.query;
  let reportsSql = '';
  postgres.query = async (sql) => {
    if (sql.includes('FROM reporte r')) {
      reportsSql = sql;
      return { rows: [] };
    }
    if (sql.includes('FROM avistamiento a')) return { rows: [] };
    throw new Error('Consulta inesperada en la prueba');
  };

  const app = express();
  app.use('/api/map', mapRoutes);
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    postgres.query = originalQuery;
    await new Promise((resolve) => server.close(resolve));
  });

  const address = server.address();
  const response = await fetch(`http://127.0.0.1:${address.port}/api/map/reports`);
  assert.equal(response.status, 200);
  assert.match(reportsSql, /r\.estado = 'ACTIVO' AND m\.estado = 'PERDIDA'/);
  assert.match(
    reportsSql,
    /r\.cerrado_en\s*>=\s*\(CURRENT_TIMESTAMP AT TIME ZONE 'UTC'\)\s*-\s*INTERVAL '30 days'/
  );
  assert.doesNotMatch(reportsSql, /r\.creado_en\s*>=/);
});

test('las imágenes públicas aplican la misma ventana de cerrado_en', async (t) => {
  const originalQuery = postgres.query;
  let imageSql = '';
  postgres.query = async (sql) => {
    imageSql = sql;
    return { rowCount: 0, rows: [] };
  };

  const app = express();
  app.use('/api/map', mapRoutes);
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    postgres.query = originalQuery;
    await new Promise((resolve) => server.close(resolve));
  });

  const address = server.address();
  const response = await fetch(
    `http://127.0.0.1:${address.port}/api/map/images/507f1f77bcf86cd799439011`
  );
  assert.equal(response.status, 404);
  assert.match(
    imageSql,
    /r\.cerrado_en\s*>=\s*\(CURRENT_TIMESTAMP AT TIME ZONE 'UTC'\)\s*-\s*INTERVAL '30 days'/
  );
});
