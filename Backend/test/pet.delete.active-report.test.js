const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const express = require('express');

const postgres = require('../src/config/postgres_db');
const images = require('../src/modules/pets/pets.images.repository');
let mongoCalls = 0;
let recoveryCalls = 0;
let clientReleased = false;
let recoveryResult = { ok: true, outcome: 'DELETED' };
images.eliminarImagenesMascotaMongo = async () => {
  mongoCalls += 1;
  return { deletedCount: 1, operationId: 'mock-operation' };
};
const { petDeletionRecovery } = require('../src/modules/pets/pets.deletion-recovery.service');
petDeletionRecovery.recover = async operationId => {
  assert.equal(operationId, 'mock-operation');
  assert.equal(clientReleased, true);
  recoveryCalls++;
  return recoveryResult;
};
const petsRouter = require('../src/modules/pets/pets.routes');
const { signAccessToken } = require('../src/utils/jwt');

async function requestDeletion(activeReport, failCommit = false) {
  clientReleased = false;
  const queries = [];
  const originalConnect = postgres.pool.connect;
  postgres.pool.connect = async () => ({
    async query(sql) {
      const normalized = sql.trim().replace(/\s+/g, ' ');
      queries.push(normalized);
      if (normalized === 'COMMIT' && failCommit) throw new Error('Simulated commit failure');
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(normalized)) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('SELECT id, estado FROM mascota')) {
        return { rowCount: 1, rows: [{ id: 7, estado: 'PERDIDA' }] };
      }
      if (normalized.includes('FROM reporte')) {
        assert.match(normalized, /estado = 'ACTIVO'/);
        return activeReport
          ? { rowCount: 1, rows: [{ id: 9 }] }
          : { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('UPDATE mascota')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Consulta inesperada: ${normalized}`);
    },
    release() { clientReleased = true; },
  });
  const app = express();
  app.use('/api/pets', petsRouter);
  const server = app.listen(0, '127.0.0.1');
  try {
    await once(server, 'listening');
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/pets/7`, {
      method: 'DELETE',
      headers: {
        Authorization: `Bearer ${signAccessToken({ sub: 3, role: 'USUARIO' })}`,
      },
    });
    return { response, body: await response.json(), queries };
  } finally {
    postgres.pool.connect = originalConnect;
    await new Promise((resolve) => server.close(resolve));
  }
}

test('no inactiva una mascota con reporte activo', async () => {
  mongoCalls = 0;
  recoveryCalls = 0;
  const { response, body, queries } = await requestDeletion(true);
  assert.equal(response.status, 409);
  assert.equal(body.code, 'ACTIVE_REPORT_EXISTS');
  assert.ok(queries.some((sql) => sql.includes('FROM reporte')));
  assert.ok(!queries.some((sql) => sql.startsWith('UPDATE mascota')));
  assert.equal(mongoCalls, 0);
  assert.equal(recoveryCalls, 0);
  assert.equal(queries.at(-1), 'ROLLBACK');
});

test('un reporte histórico finalizado no bloquea la eliminación', async () => {
  mongoCalls = 0;
  const { response, queries } = await requestDeletion(false);
  assert.equal(response.status, 200);
  assert.ok(queries.some((sql) => sql.startsWith('UPDATE mascota')));
  assert.equal(mongoCalls, 1);
  assert.equal(queries.at(-1), 'COMMIT');
});

test('si falla COMMIT, recupera solo después de liberar la transacción anterior', async () => {
  recoveryCalls = 0;
  const { response, queries } = await requestDeletion(false, true);
  assert.equal(response.status, 500);
  assert.equal(queries.at(-1), 'ROLLBACK');
  assert.equal(recoveryCalls, 1);
});

test('no responde éxito cuando la verificación persistente queda pendiente', async () => {
  recoveryResult = { ok: false };
  try {
    const { response } = await requestDeletion(false);
    assert.equal(response.status, 500);
  } finally {
    recoveryResult = { ok: true, outcome: 'DELETED' };
  }
});
