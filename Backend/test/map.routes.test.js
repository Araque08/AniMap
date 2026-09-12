const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const express = require('express');

const postgres = require('../src/config/postgres_db');
const mapRoutes = require('../src/modules/map/map.routes');

function reportRow({ id, mostrarContacto }) {
  return {
    reporte_id: id,
    reporte_descripcion: 'Reporte temporal',
    reporte_estado: 'ACTIVO',
    creado_en: new Date('2026-09-12T12:00:00.000Z'),
    cerrado_en: null,
    mostrar_contacto: mostrarContacto,
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
          reporter_name: 'Autor existente',
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
  assert.equal(hidden.showContact, false);
  assert.equal(hidden.ownerPhone, '');
  assert.equal(hidden.ownerName, '');
  assert.equal(hidden.ownerEmail, '');

  const authorized = body.data.find((item) => item.id === 'lost_2');
  assert.equal(authorized.showContact, true);
  assert.equal(authorized.ownerPhone, '3000000000');
  assert.equal(authorized.ownerName, '');
  assert.equal(authorized.ownerEmail, '');

  const sighting = body.data.find((item) => item.id === 'sighting_3');
  assert.equal(sighting.ownerName, 'Autor existente');
});
