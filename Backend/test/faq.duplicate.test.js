const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { createFaqService, faqService } = require('../src/modules/faq/faq.service');
const faqRoutes = require('../src/modules/faq/faq.routes');
const errorMiddleware = require('../src/middleware/error.middleware');
const { signAccessToken } = require('../src/utils/jwt');

const duplicateMessage = 'Ya existe una pregunta frecuente igual en esta categoría.';

function fakePool() {
  const state = { faqs: [], audits: [], queries: [], failAudit: false };
  const locks = new Map();
  let nextId = 1;
  const normalize = (question) => question.trim().toLocaleLowerCase();

  return {
    state,
    async connect() {
      let pendingFaq = null;
      let pendingAudit = null;
      let releaseLock = null;
      return {
        async query(sql, params = []) {
          state.queries.push({ sql, params });
          if (sql === 'BEGIN') return {};
          if (sql.startsWith('SELECT id FROM categoria_faq')) {
            return { rowCount: 1, rows: [{ id: params[0] }] };
          }
          if (sql.startsWith('SELECT pg_advisory_xact_lock')) {
            const key = `${params[0]}:${normalize(params[1])}`;
            const previous = locks.get(key);
            let release;
            const current = new Promise((resolve) => { release = resolve; });
            locks.set(key, current);
            if (previous) await previous;
            releaseLock = () => {
              release();
              if (locks.get(key) === current) locks.delete(key);
            };
            return { rows: [{}] };
          }
          if (sql.includes('FROM faq WHERE id = $1 FOR UPDATE')) {
            const current = state.faqs.find((faq) => faq.id === params[0]);
            return {
              rowCount: current ? 1 : 0,
              rows: current ? [{ same_key: current.fk_categoria === params[1] &&
                normalize(current.pregunta) === normalize(params[2]) }] : [],
            };
          }
          if (sql.startsWith('SELECT id FROM faq')) {
            await new Promise((resolve) => setImmediate(resolve));
            const found = state.faqs.find((faq) =>
              faq.fk_categoria === params[0] &&
              normalize(faq.pregunta) === normalize(params[1]) &&
              (params.length < 3 || faq.id !== params[2]));
            return { rowCount: found ? 1 : 0, rows: found ? [{ id: found.id }] : [] };
          }
          if (sql.startsWith('INSERT INTO faq')) {
            pendingFaq = {
              id: nextId++, fk_categoria: params[0], pregunta: params[1],
              respuesta: params[2], activa: params[3],
            };
            return { rowCount: 1, rows: [pendingFaq] };
          }
          if (sql.startsWith('UPDATE faq SET fk_categoria')) {
            const existing = state.faqs.find((faq) => faq.id === params[4]);
            pendingFaq = existing && {
              id: existing.id, fk_categoria: params[0], pregunta: params[1],
              respuesta: params[2], activa: params[3],
            };
            return { rowCount: pendingFaq ? 1 : 0, rows: pendingFaq ? [pendingFaq] : [] };
          }
          if (sql.includes('INSERT INTO bitacora_administrativa')) {
            if (state.failAudit) throw new Error('Fallo simulado de bitácora');
            pendingAudit = { adminId: params[0], action: params[1], faqId: params[3] };
            return {};
          }
          if (sql === 'COMMIT') {
            if (pendingFaq) {
              state.faqs = state.faqs.filter((faq) => faq.id !== pendingFaq.id);
              state.faqs.push(pendingFaq);
            }
            if (pendingAudit) state.audits.push(pendingAudit);
            releaseLock?.();
            releaseLock = null;
            return {};
          }
          if (sql === 'ROLLBACK') {
            pendingFaq = null;
            pendingAudit = null;
            releaseLock?.();
            releaseLock = null;
            return {};
          }
          throw new Error(`Consulta no simulada: ${sql}`);
        },
        release() { releaseLock?.(); },
      };
    },
  };
}

const input = (categoryId, question, answer = 'Respuesta') => ({
  categoriaId: categoryId, pregunta: question, respuesta: answer, activa: true,
});

test('crear compara trim y mayúsculas dentro de la categoría y audita solo altas reales', async () => {
  const pool = fakePool();
  const service = createFaqService(pool);
  await service.createFaq(input(1, '¿Cómo RECUPERAR mi contraseña?'), 7);
  await assert.rejects(
    service.createFaq(input(1, '  ¿cómo recuperar mi contraseña?  '), 7),
    { statusCode: 409, code: 'FAQ_DUPLICATE', message: duplicateMessage }
  );
  await service.createFaq(input(2, '¿cómo recuperar mi contraseña?'), 7);
  assert.equal(pool.state.faqs.length, 2);
  assert.equal(pool.state.audits.length, 2);
  assert.match(pool.state.queries.find(({ sql }) => sql.startsWith('SELECT id FROM faq')).sql,
    /lower\(btrim\(pregunta\)\) = lower\(btrim\(\$2::text\)\)/);
  assert.equal(pool.state.queries.filter(({ sql }) => sql.startsWith('SELECT pg_advisory_xact_lock')).length, 3);
});

test('dos creaciones concurrentes idénticas producen una fila, un 409 y una bitácora', async () => {
  const pool = fakePool();
  const service = createFaqService(pool);
  const results = await Promise.allSettled([
    service.createFaq(input(1, 'Pregunta simultánea'), 7),
    service.createFaq(input(1, '  PREGUNTA SIMULTÁNEA  '), 7),
  ]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(results.filter((result) => result.status === 'rejected' &&
    result.reason.statusCode === 409).length, 1);
  assert.equal(pool.state.faqs.length, 1);
  assert.equal(pool.state.audits.length, 1);
  assert.equal(pool.state.queries.filter(({ sql }) => sql === 'COMMIT').length, 1);
  assert.equal(pool.state.queries.filter(({ sql }) => sql === 'ROLLBACK').length, 1);
});

test('editar la propia FAQ permite cambiar respuesta, pero rechaza pregunta ajena', async () => {
  const pool = fakePool();
  const service = createFaqService(pool);
  const first = await service.createFaq(input(1, 'Primera'), 7);
  const second = await service.createFaq(input(1, 'Segunda'), 7);
  await service.updateFaq(first.id, input(1, '  PRIMERA  ', 'Nueva respuesta'), 7);
  await assert.rejects(
    service.updateFaq(second.id, input(1, ' primera '), 7),
    { statusCode: 409, code: 'FAQ_DUPLICATE' }
  );
  await service.updateFaq(second.id, input(2, 'Primera'), 7);
  assert.equal(pool.state.faqs.length, 2);
  assert.equal(pool.state.faqs.find((faq) => faq.id === first.id).respuesta, 'Nueva respuesta');
  assert.equal(pool.state.faqs.find((faq) => faq.id === second.id).fk_categoria, 2);
  assert.deepEqual(pool.state.audits.map((audit) => audit.action),
    ['CREAR', 'CREAR', 'EDITAR', 'EDITAR']);
});

test('editar solo la respuesta de un duplicado antiguo no crea otra fila', async () => {
  const pool = fakePool();
  pool.state.faqs.push(
    { id: 100, fk_categoria: 1, pregunta: 'Duplicada antigua', respuesta: 'A', activa: true },
    { id: 101, fk_categoria: 1, pregunta: '  DUPLICADA ANTIGUA  ', respuesta: 'B', activa: true }
  );
  const service = createFaqService(pool);
  await service.updateFaq(100, input(1, 'Duplicada antigua', 'Respuesta editada'), 7);
  assert.equal(pool.state.faqs.length, 2);
  assert.equal(pool.state.faqs.find((faq) => faq.id === 100).respuesta, 'Respuesta editada');
  assert.equal(pool.state.audits.length, 1);
  assert.equal(pool.state.queries.filter(({ sql }) => sql.startsWith('SELECT pg_advisory_xact_lock')).length, 0);
});

test('dos ediciones concurrentes hacia la misma pregunta no generan duplicado', async () => {
  const pool = fakePool();
  const service = createFaqService(pool);
  const first = await service.createFaq(input(1, 'Primera'), 7);
  const second = await service.createFaq(input(1, 'Segunda'), 7);
  const results = await Promise.allSettled([
    service.updateFaq(first.id, input(1, 'Compartida'), 7),
    service.updateFaq(second.id, input(1, ' COMPARTIDA '), 7),
  ]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(results.filter((result) => result.status === 'rejected' &&
    result.reason.statusCode === 409).length, 1);
  assert.equal(pool.state.faqs.filter((faq) => faq.pregunta.toLowerCase() === 'compartida').length, 1);
  assert.equal(pool.state.audits.filter((audit) => audit.action === 'EDITAR').length, 1);
});

test('fallo de bitácora revierte creación y edición', async () => {
  const pool = fakePool();
  const service = createFaqService(pool);
  pool.state.failAudit = true;
  await assert.rejects(service.createFaq(input(1, 'Temporal'), 7), /Fallo simulado/);
  assert.equal(pool.state.faqs.length, 0);
  assert.equal(pool.state.audits.length, 0);
  pool.state.failAudit = false;
  const created = await service.createFaq(input(1, 'Original'), 7);
  pool.state.failAudit = true;
  await assert.rejects(service.updateFaq(created.id, input(1, 'Cambiada'), 7), /Fallo simulado/);
  assert.equal(pool.state.faqs[0].pregunta, 'Original');
  assert.equal(pool.state.audits.length, 1);
});

test('POST y PUT exigen ADMINISTRADOR y devuelven 409 controlado', async () => {
  const originalCreate = faqService.createFaq;
  const originalUpdate = faqService.updateFaq;
  faqService.createFaq = async () => {
    throw Object.assign(new Error(duplicateMessage), { statusCode: 409, code: 'FAQ_DUPLICATE' });
  };
  faqService.updateFaq = faqService.createFaq;
  const app = express();
  app.use(express.json());
  app.use('/api/faqs', faqRoutes);
  app.use(errorMiddleware);
  const server = app.listen(0, '127.0.0.1');
  try {
    await new Promise((resolve) => server.once('listening', resolve));
    const url = `http://127.0.0.1:${server.address().port}/api/faqs`;
    const userToken = signAccessToken({ sub: 2, role: 'USUARIO', deviceId: 'test' });
    const adminToken = signAccessToken({ sub: 3, role: 'ADMINISTRADOR', deviceId: 'test' });
    for (const [method, path] of [['POST', ''], ['PUT', '/1']]) {
      const options = (token) => ({ method, headers: {
        Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
      }, body: JSON.stringify(input(1, 'Duplicada')) });
      assert.equal((await fetch(url + path, options(userToken))).status, 403);
      const response = await fetch(url + path, options(adminToken));
      assert.equal(response.status, 409);
      assert.deepEqual(await response.json(), {
        ok: false, code: 'FAQ_DUPLICATE', message: duplicateMessage,
      });
    }
  } finally {
    faqService.createFaq = originalCreate;
    faqService.updateFaq = originalUpdate;
    await new Promise((resolve) => server.close(resolve));
  }
});
