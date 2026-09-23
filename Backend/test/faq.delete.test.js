const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { createFaqService, faqService } = require('../src/modules/faq/faq.service');
const faqRoutes = require('../src/modules/faq/faq.routes');
const errorMiddleware = require('../src/middleware/error.middleware');
const { signAccessToken } = require('../src/utils/jwt');

function fakeFaqPool({ failAudit = false } = {}) {
  const state = {
    categories: [{ id: 10, nombre: 'Cuenta y acceso' }],
    faqs: [
      { id: 1, fk_categoria: 10, pregunta: 'FAQ A', respuesta: 'A', activa: true },
      { id: 2, fk_categoria: 10, pregunta: 'FAQ B', respuesta: 'B', activa: true },
    ],
    audits: [],
  };
  let pending;
  return {
    state,
    async query(sql, params = []) {
      if (sql.includes('FROM categoria_faq c LEFT JOIN faq')) {
        return { rows: state.categories.map((category) => ({ ...category,
          total_faq: state.faqs.filter((faq) => faq.fk_categoria === category.id).length })) };
      }
      if (sql.includes('FROM faq f JOIN categoria_faq c')) {
        let rows = state.faqs.filter((faq) => !sql.includes('f.activa = TRUE') || faq.activa);
        if (sql.includes('WHERE f.id = $1')) rows = rows.filter((faq) => faq.id === params[0]);
        return { rows: rows.map((faq) => ({ ...faq, categoria: state.categories[0].nombre })), rowCount: rows.length };
      }
      throw new Error(`Consulta no simulada: ${sql}`);
    },
    async connect() {
      return {
        async query(sql, params = []) {
          if (sql === 'BEGIN') {
            pending = { faqs: state.faqs.map((faq) => ({ ...faq })), audits: [...state.audits] };
            return {};
          }
          if (sql.startsWith('DELETE FROM faq WHERE id')) {
            const found = pending.faqs.find((faq) => faq.id === params[0]);
            pending.faqs = pending.faqs.filter((faq) => faq.id !== params[0]);
            return { rowCount: found ? 1 : 0, rows: found ? [{ id: found.id }] : [] };
          }
          if (sql.startsWith('UPDATE faq SET activa')) {
            const found = pending.faqs.find((faq) => faq.id === params[1]);
            if (found) found.activa = params[0];
            return { rowCount: found ? 1 : 0, rows: found ? [found] : [] };
          }
          if (sql.includes('INSERT INTO bitacora_administrativa')) {
            if (failAudit) throw new Error('Fallo simulado de bitácora');
            pending.audits.push({ adminId: params[0], action: params[1], entity: params[2], id: params[3], sql });
            return {};
          }
          if (sql === 'COMMIT') {
            state.faqs = pending.faqs;
            state.audits = pending.audits;
            pending = null;
            return {};
          }
          if (sql === 'ROLLBACK') {
            pending = null;
            return {};
          }
          throw new Error(`Consulta no simulada: ${sql}`);
        },
        release() {},
      };
    },
  };
}

test('DELETE borra solo la FAQ indicada, audita y conserva categoría y otras FAQ', async () => {
  const pool = fakeFaqPool();
  const service = createFaqService(pool);
  assert.deepEqual(await service.deleteFaq(1, 7), { deleted: true, id: 1 });
  assert.deepEqual(pool.state.faqs.map((faq) => faq.id), [2]);
  assert.deepEqual(pool.state.categories.map((category) => category.id), [10]);
  assert.equal(pool.state.audits.length, 1);
  const { adminId, action, entity, id } = pool.state.audits[0];
  assert.deepEqual({ adminId, action, entity, id },
    { adminId: 7, action: 'ELIMINAR', entity: 'faq', id: 1 });
  assert.match(pool.state.audits[0].sql, /fk_admin, modulo, accion, entidad_afectada, id_entidad_afectada/);
  assert.deepEqual((await service.listFaqs({ admin: true })).map((faq) => faq.id), [2]);
  assert.deepEqual((await service.listFaqs()).map((faq) => faq.id), [2]);
  assert.equal((await service.listCategories())[0].total_faq, 1);
  await assert.rejects(service.getPublicFaq(1), { code: 'FAQ_NOT_FOUND', statusCode: 404 });
  assert.equal((await service.getPublicFaq(2)).id, 2);
  await assert.rejects(service.setFaqStatus(1, true, 7), { code: 'FAQ_NOT_FOUND', statusCode: 404 });
  assert.deepEqual(pool.state.faqs.map((faq) => faq.id), [2]);
  await service.deleteFaq(2, 7);
  assert.equal((await service.listCategories())[0].total_faq, 0);
  assert.deepEqual(pool.state.categories.map((category) => category.id), [10]);
});

test('ID inválido e inexistente se rechazan sin borrar otras FAQ', async () => {
  const pool = fakeFaqPool();
  const service = createFaqService(pool);
  await assert.rejects(service.deleteFaq('no-id', 7), { statusCode: 400, code: 'INVALID_ID' });
  await assert.rejects(service.deleteFaq(99, 7), { statusCode: 404, code: 'FAQ_NOT_FOUND' });
  assert.deepEqual(pool.state.faqs.map((faq) => faq.id), [1, 2]);
  assert.equal(pool.state.audits.length, 0);
});

test('si falla la bitácora, DELETE se revierte y la FAQ permanece', async () => {
  const pool = fakeFaqPool({ failAudit: true });
  const service = createFaqService(pool);
  await assert.rejects(service.deleteFaq(1, 7), /Fallo simulado de bitácora/);
  assert.deepEqual(pool.state.faqs.map((faq) => faq.id), [1, 2]);
  assert.equal(pool.state.audits.length, 0);
});

test('DELETE /api/faqs/:id exige JWT y ADMINISTRADOR y devuelve 404 controlado', async () => {
  const original = faqService.deleteFaq;
  faqService.deleteFaq = async (id, adminId) => {
    if (id === '99') throw Object.assign(new Error('Pregunta frecuente no encontrada'),
      { statusCode: 404, code: 'FAQ_NOT_FOUND' });
    assert.equal(adminId, 7);
    return { deleted: true, id: Number(id) };
  };
  const app = express();
  app.use(express.json());
  app.use('/api/faqs', faqRoutes);
  app.use(errorMiddleware);
  const server = app.listen(0, '127.0.0.1');
  try {
    await new Promise((resolve) => server.once('listening', resolve));
    const url = `http://127.0.0.1:${server.address().port}/api/faqs/1`;
    assert.equal((await fetch(url, { method: 'DELETE' })).status, 401);
    const userToken = signAccessToken({ sub: 8, role: 'USUARIO', deviceId: 'test' });
    assert.equal((await fetch(url, { method: 'DELETE', headers: {
      Authorization: `Bearer ${userToken}`, 'Content-Type': 'application/json',
    }, body: JSON.stringify({ role: 'ADMINISTRADOR' }) })).status, 403);
    const adminToken = signAccessToken({ sub: 7, role: 'ADMINISTRADOR', deviceId: 'test' });
    const headers = { Authorization: `Bearer ${adminToken}` };
    const deleted = await fetch(url, { method: 'DELETE', headers });
    assert.equal(deleted.status, 200);
    assert.deepEqual((await deleted.json()).data, { deleted: true, id: 1 });
    const missing = await fetch(url.replace(/\/1$/, '/99'), { method: 'DELETE', headers });
    assert.equal(missing.status, 404);
    assert.equal((await missing.json()).code, 'FAQ_NOT_FOUND');
  } finally {
    faqService.deleteFaq = original;
    await new Promise((resolve) => server.close(resolve));
  }
});
