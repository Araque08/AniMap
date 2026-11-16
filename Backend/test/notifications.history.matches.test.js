const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/postgres_db');
const { obtenerHistorialNotificaciones } = require('../src/modules/notifications/notifications.history.service');

function mockQueries(t, query) {
  const original = db.pool.query;
  db.pool.query = query;
  t.after(() => { db.pool.query = original; });
}

test('historial HU034 conserva paginación y enlaza solo coincidencias del destinatario', async t => {
  const calls = [];
  mockQueries(t, async (sql, values) => {
    calls.push({ sql, values });
    if (calls.length === 1) {
      assert.match(sql, /WHERE fk_usuario = \$1/);
      return { rows: Array.from({ length: 21 }, (_, i) => ({ id: i + 1,
        tipo: i === 0 || i === 20 ? 'COINCIDENCIA_FOTOGRAFICA' : 'ADMINISTRATIVA' })) };
    }
    assert.match(sql, /WHERE c\.fk_usuario = \$1/);
    assert.match(sql, /c\.fk_notificacion = ANY\(\$2::integer\[\]\)/);
    assert.deepEqual(values, [7, [1]]);
    return { rows: [{ notificationId: 1, matchId: 12 }] };
  });
  const result = await obtenerHistorialNotificaciones(7);
  assert.equal(result.notificaciones[0].matchId, 12);
  assert.equal(result.notificaciones[1].matchId, undefined);
  assert.equal(result.notificaciones.length, 20);
  assert.equal(result.hayMas, true);
  assert.equal(calls.length, 2);
});

test('sin coincidencia autorizada no inventa un destino privado', async t => {
  let calls = 0;
  mockQueries(t, async () => ({ rows: ++calls === 1
    ? [{ id: 1, tipo: 'COINCIDENCIA_FOTOGRAFICA' }] : [] }));
  const result = await obtenerHistorialNotificaciones(8);
  assert.equal(result.notificaciones[0].matchId, null);
});

test('historial general sigue disponible si la migración opcional HU034 no está instalada', async t => {
  let calls = 0;
  mockQueries(t, async () => {
    if (++calls === 1) return { rows: [{ id: 1, tipo: 'COINCIDENCIA_FOTOGRAFICA' }] };
    throw Object.assign(new Error('isolated missing relation'), { code: '42P01' });
  });
  const result = await obtenerHistorialNotificaciones(7);
  assert.equal(result.notificaciones[0].matchId, null);
});

test('errores temporales de SQL no se presentan como coincidencias inexistentes', async t => {
  let calls = 0;
  mockQueries(t, async () => {
    if (++calls === 1) return { rows: [{ id: 1, tipo: 'COINCIDENCIA_FOTOGRAFICA' }] };
    throw Object.assign(new Error('isolated connection failure'), { code: 'ECONNRESET' });
  });
  await assert.rejects(obtenerHistorialNotificaciones(7), { code: 'ECONNRESET' });
});

test('avisos administrativos y comunitarios no consultan ni reciben destinos HU034', async t => {
  let calls = 0;
  const rows = [{ id: 1, tipo: 'ADMINISTRATIVA' }, { id: 2, tipo: 'PERDIDA_CERCANA' }];
  mockQueries(t, async () => { calls++; return { rows }; });
  assert.deepEqual((await obtenerHistorialNotificaciones(7)).notificaciones, rows);
  assert.equal(calls, 1);
});
