const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const express = require('express');
const { createUsersService, usersService } = require('../src/modules/users/users.service');
const { signAccessToken } = require('../src/utils/jwt');
require('../test-support/auth-fixture.cjs').installAuthFixture({ 1: 'ADMINISTRADOR', 2: 'USUARIO' });

test('todas las operaciones administrativas exigen JWT y ADMINISTRADOR', async () => {
  let serviceCalls = 0;
  const originals = { ...usersService };
  for (const method of Object.keys(originals)) {
    usersService[method] = async () => { serviceCalls++; return { id: 10 }; };
  }
  const app = express();
  app.use(express.json());
  app.use('/api/users', require('../src/modules/users/users.routes'));
  const server = app.listen(0, '127.0.0.1');
  try {
    await once(server, 'listening');
    for (const [method, suffix] of [['GET', ''], ['GET', '/10'], ['POST', ''], ['PUT', '/10'], ['PATCH', '/10/status'], ['DELETE', '/10']]) {
      const url = `http://127.0.0.1:${server.address().port}/api/users${suffix}`;
      assert.equal((await fetch(url, { method })).status, 401);
      assert.equal((await fetch(url, { method, headers: { Authorization: `Bearer ${signAccessToken({ sub: 2, role: 'USUARIO', deviceId: 'test-device' })}` } })).status, 403);
      assert.equal(serviceCalls, 0);
      const response = await fetch(url, { method,
        headers: { Authorization: `Bearer ${signAccessToken({ sub: 1, role: 'ADMINISTRADOR', deviceId: 'test-device' })}`, 'Content-Type': 'application/json' },
        ...(['POST', 'PUT', 'PATCH'].includes(method) ? { body: JSON.stringify({ estado: 'SUSPENDIDO' }) } : {}),
      });
      assert.equal(response.status, method === 'POST' ? 201 : 200);
      serviceCalls = 0;
    }
  } finally {
    Object.assign(usersService, originals);
    await new Promise(resolve => server.close(resolve));
  }
});

function fixture(failAudit = false) {
  const calls = [];
  const row = { id: 10, nombre: 'Temporal', email: 'temporary@example.invalid', is_verified: true, estado_cuenta: 'ACTIVO' };
  const client = {
    async query(sql, values) {
      const text = sql.trim().replace(/\s+/g, ' ');
      calls.push({ text, values });
      if (text.startsWith('SELECT id FROM usuario')) return { rowCount: 0, rows: [] };
      if (text.startsWith('SELECT id FROM rol')) return { rowCount: 1, rows: [{ id: 2 }] };
      if (text.startsWith('INSERT INTO bitacora_administrativa') && failAudit) throw new Error('Simulated audit failure');
      return { rowCount: 1, rows: [row] };
    },
    release() {},
  };
  return { calls, service: createUsersService({ connect: async () => client, query: client.query }) };
}

const input = { nombre: 'Temporal', email: 'temporary@example.invalid', password: 'test-only-password', rol: 'USUARIO' };
test('alta administrativa conserva usuario verificado, perfil, rol y auditoría transaccionales', async () => {
  const { service, calls } = fixture();
  const user = await service.createUser(input, 1);
  assert.equal(user.rol, 'USUARIO');
  assert.equal(user.is_verified, true);
  assert.equal('password_hash' in user, false);
  for (const table of ['usuario', 'perfil', 'usuario_rol', 'bitacora_administrativa']) {
    assert.ok(calls.some(({ text }) => text.startsWith(`INSERT INTO ${table}`)));
  }
  assert.equal(calls[0].text, 'BEGIN');
  assert.equal(calls.at(-1).text, 'COMMIT');
});

test('fallo de auditoría administrativa revierte el alta completa', async () => {
  const { service, calls } = fixture(true);
  await assert.rejects(service.createUser(input, 1), /Simulated audit failure/);
  assert.equal(calls.at(-1).text, 'ROLLBACK');
  assert.ok(!calls.some(({ text }) => text === 'COMMIT'));
});

test('suspensión revoca sesiones en la misma transacción y no permite desactivar al propio admin', async () => {
  const { service, calls } = fixture();
  await service.setUserStatus(10, 'SUSPENDIDO', 1);
  assert.ok(calls.some(({ text, values }) => text.startsWith('UPDATE device_session') && values[0] === 10));
  assert.equal(calls.at(-1).text, 'COMMIT');
  const before = calls.length;
  await assert.rejects(service.setUserStatus(1, 'SUSPENDIDO', 1), error => error.statusCode === 409);
  await assert.rejects(service.deleteUser(1, 1), error => error.statusCode === 409);
  assert.equal(calls.length, before);
});
