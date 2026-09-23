const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { createFaqService, faqService } = require('../src/modules/faq/faq.service');
const faqRoutes = require('../src/modules/faq/faq.routes');
const errorMiddleware = require('../src/middleware/error.middleware');
const { signAccessToken } = require('../src/utils/jwt');

test('FAQ pública lista solo activas y detalle archivado responde 404', async () => {
  const queries = [];
  const service = createFaqService({ query: async (sql) => {
    queries.push(sql);
    return sql.includes('WHERE f.id') ? { rowCount: 0, rows: [] } : { rows: [] };
  } });
  assert.deepEqual(await service.listFaqs(), []);
  assert.match(queries[0], /f\.activa = TRUE/);
  await assert.rejects(service.getPublicFaq(9), { statusCode: 404 });
  assert.match(queries[1], /f\.activa = TRUE/);
  await service.listFaqs({ admin: true });
  assert.doesNotMatch(queries[2], /f\.activa = TRUE/);
});

test('categoría con FAQ asociada no se elimina y revierte', async () => {
  const calls = [];
  const client = {
    async query(sql) {
      calls.push(sql);
      if (sql.includes('FROM faq WHERE fk_categoria')) return { rowCount: 1, rows: [{ id: 1 }] };
      return { rowCount: 0, rows: [] };
    },
    release() {},
  };
  const service = createFaqService({ connect: async () => client });
  await assert.rejects(service.deleteCategory(3, 7), { code: 'FAQ_CATEGORY_IN_USE' });
  assert.ok(calls.includes('ROLLBACK'));
  assert.ok(!calls.some((sql) => sql.startsWith('DELETE')));
});

test('crear FAQ registra auditoría y confirma en una transacción mock', async () => {
  const calls = [];
  const client = {
    async query(sql) {
      calls.push(sql);
      if (sql.startsWith('SELECT id FROM categoria_faq')) return { rowCount: 1, rows: [{ id: 2 }] };
      if (sql.startsWith('SELECT id FROM faq')) return { rowCount: 0, rows: [] };
      if (sql.includes('INSERT INTO faq')) return { rowCount: 1, rows: [{ id: 8, pregunta: 'Prueba' }] };
      return { rowCount: 1, rows: [] };
    },
    release() {},
  };
  const service = createFaqService({ connect: async () => client });
  const created = await service.createFaq({ categoriaId: 2, pregunta: ' Prueba ', respuesta: ' Respuesta ' }, 7);
  assert.equal(created.id, 8);
  assert.equal(calls[0], 'BEGIN');
  assert.ok(calls.some((sql) => sql.includes('INSERT INTO bitacora_administrativa')));
  assert.equal(calls.at(-1), 'COMMIT');
});

test('editar y activar o archivar FAQ usan transacciones auditadas', async () => {
  const calls = [];
  const client = {
    async query(sql, params) {
      calls.push({ sql, params });
      if (sql.startsWith('SELECT id FROM categoria_faq')) return { rowCount: 1, rows: [{ id: 2 }] };
      if (sql.includes('FROM faq WHERE id = $1 FOR UPDATE')) return { rowCount: 1, rows: [{ same_key: false }] };
      if (sql.startsWith('SELECT id FROM faq')) return { rowCount: 0, rows: [] };
      if (sql.startsWith('UPDATE faq')) return { rowCount: 1, rows: [{ id: 8, activa: params[0] === false ? false : true }] };
      return { rowCount: 1, rows: [] };
    },
    release() {},
  };
  const service = createFaqService({ connect: async () => client });
  await service.updateFaq(8, { categoriaId: 2, pregunta: 'Editada', respuesta: 'R', activa: true }, 7);
  await service.setFaqStatus(8, false, 7);
  await service.setFaqStatus(8, true, 7);
  assert.equal(calls.filter(({ sql }) => sql === 'COMMIT').length, 3);
  assert.equal(calls.filter(({ sql }) => sql.includes('INSERT INTO bitacora_administrativa')).length, 3);
  assert.ok(calls.some(({ sql, params }) => sql.startsWith('UPDATE faq SET activa') && params[0] === false));
  assert.ok(calls.some(({ sql, params }) => sql.startsWith('UPDATE faq SET activa') && params[0] === true));
});

test('categorías se listan, crean, editan y eliminan solo sin FAQ', async () => {
  const calls = [];
  const client = {
    async query(sql, params) {
      calls.push({ sql, params });
      if (sql.startsWith('INSERT INTO categoria_faq')) return { rowCount: 1, rows: [{ id: 4, nombre: 'Nueva' }] };
      if (sql.startsWith('UPDATE categoria_faq')) return { rowCount: 1, rows: [{ id: 4, nombre: 'Editada' }] };
      if (sql.startsWith('SELECT 1 FROM faq')) return { rowCount: 0, rows: [] };
      if (sql.startsWith('DELETE FROM categoria_faq')) return { rowCount: 1, rows: [{ id: 4 }] };
      return { rowCount: 1, rows: [{ id: 4, nombre: 'Nueva', total_faq: 0 }] };
    },
    release() {},
  };
  const service = createFaqService({ query: client.query.bind(client), connect: async () => client });
  assert.equal((await service.listCategories())[0].id, 4);
  assert.equal((await service.createCategory({ nombre: 'Nueva' }, 7)).id, 4);
  assert.equal((await service.updateCategory(4, { nombre: 'Editada' }, 7)).nombre, 'Editada');
  assert.deepEqual(await service.deleteCategory(4, 7), { deleted: true, id: 4 });
  assert.equal(calls.filter(({ sql }) => sql === 'COMMIT').length, 3);
});

test('rutas administrativas exigen JWT y ADMINISTRADOR', async () => {
  const original = faqService.listFaqs;
  faqService.listFaqs = async () => [];
  const app = express();
  app.use(express.json());
  app.use('/api/faqs', faqRoutes);
  app.use(errorMiddleware);
  const server = app.listen(0, '127.0.0.1');
  try {
    await new Promise((resolve) => server.once('listening', resolve));
    const url = `http://127.0.0.1:${server.address().port}/api/faqs/admin`;
    assert.equal((await fetch(url)).status, 401);
    const userToken = signAccessToken({ sub: 2, role: 'USUARIO', deviceId: 'test' });
    assert.equal((await fetch(url, { headers: { Authorization: `Bearer ${userToken}` } })).status, 403);
    const adminToken = signAccessToken({ sub: 3, role: 'ADMINISTRADOR', deviceId: 'test' });
    const response = await fetch(url, { headers: { Authorization: `Bearer ${adminToken}` } });
    assert.equal(response.status, 200);
    assert.deepEqual((await response.json()).data, []);
  } finally {
    faqService.listFaqs = original;
    await new Promise((resolve) => server.close(resolve));
  }
});
