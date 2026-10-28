const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { once } = require('node:events');
const db = require('../src/config/postgres_db');
const router = require('../src/modules/map/map.routes');

async function request(t, query) {
  const calls = [];
  t.mock.method(db, 'query', async (sql, values) => {
    calls.push({ sql, values });
    return { rows: [] };
  });
  const app = express();
  app.use('/map', router);
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const response = await fetch(`http://127.0.0.1:${server.address().port}/map/reports?${query}`);
  return { response, calls };
}

test('filtros combinados parametrizan ambas consultas y usan la fecha del evento', async t => {
  const { response, calls } = await request(t,
    'species=Perro&color=Caf%C3%A9&from=2026-10-01&to=2026-10-17&status=active');
  assert.equal(response.status, 200);
  assert.equal(calls.length, 2);
  for (const { sql, values } of calls) {
    assert.deepEqual(values, ['perro', 'café', '2026-10-01', '2026-10-17']);
    assert.match(sql, /LOWER\(BTRIM\(e.nombre\)\) = \$1/);
    assert.match(sql, /LOWER\(BTRIM\(m.color\)\) = \$2/);
    assert.match(sql, /America\/Bogota/);
    assert.match(sql, /\$4::date \+ INTERVAL '1 day'/);
  }
  assert.match(calls[0].sql, /CASE WHEN r.estado = 'FINALIZADO' THEN r.cerrado_en ELSE r.creado_en END/);
  assert.match(calls[1].sql, /a.fecha_hora >=/);
});

for (const query of ['from=2026-02-30', 'from=2026-10-17&to=2026-10-01',
  'status=unknown', 'species=a&species=b', 'color=' + 'x'.repeat(101)]) {
  test(`filtro inválido no consulta PostgreSQL: ${query.slice(0, 55)}`, async t => {
    const { response, calls } = await request(t, query);
    assert.equal(response.status, 400);
    assert.equal((await response.json()).code, 'INVALID_MAP_FILTERS');
    assert.equal(calls.length, 0);
  });
}

test('Encontrados no mezcla avistamientos y limpiar no filtra por propietario', async t => {
  const { response, calls } = await request(t, 'status=found');
  assert.equal(response.status, 200);
  assert.equal(calls.length, 1);
  assert.match(calls[0].sql, /AND r.estado = 'FINALIZADO'/);
  assert.doesNotMatch(calls[0].sql, /WHERE r.fk_usuario/);
});
