const db = require('../../config/postgres_db');

function httpError(message, statusCode, code) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.code = code;
  return error;
}

function positiveId(value) {
  const id = Number(value);
  if (!Number.isInteger(id) || id <= 0) throw httpError('ID inválido', 400, 'INVALID_ID');
  return id;
}

function requiredText(value, label, maxLength) {
  const text = typeof value === 'string' ? value.trim() : '';
  if (!text || (maxLength && text.length > maxLength)) {
    throw httpError(`${label} inválido`, 400, 'INVALID_FAQ_INPUT');
  }
  return text;
}

function createFaqService(pool = db.pool) {
  async function listCategories() {
    const result = await pool.query(
      `SELECT c.id, c.nombre, c.descripcion,
              COUNT(f.id)::INT AS total_faq,
              COUNT(f.id) FILTER (WHERE f.activa = TRUE)::INT AS total_activas
       FROM categoria_faq c LEFT JOIN faq f ON f.fk_categoria = c.id
       GROUP BY c.id, c.nombre, c.descripcion ORDER BY c.nombre ASC`
    );
    return result.rows;
  }

  async function listFaqs({ categoryId, search, admin = false } = {}) {
    const values = [];
    const conditions = admin ? [] : ['f.activa = TRUE'];
    if (categoryId !== undefined && categoryId !== null && categoryId !== '') {
      values.push(positiveId(categoryId));
      conditions.push(`f.fk_categoria = $${values.length}`);
    }
    if (search && String(search).trim()) {
      values.push(`%${String(search).trim()}%`);
      conditions.push(`(f.pregunta ILIKE $${values.length} OR f.respuesta ILIKE $${values.length})`);
    }
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const result = await pool.query(
      `SELECT f.id, f.fk_categoria, c.nombre AS categoria,
              f.pregunta, f.respuesta, f.activa
       FROM faq f JOIN categoria_faq c ON c.id = f.fk_categoria
       ${where} ORDER BY c.nombre ASC, f.id DESC`,
      values
    );
    return result.rows;
  }

  async function getPublicFaq(id) {
    const result = await pool.query(
      `SELECT f.id, f.fk_categoria, c.nombre AS categoria,
              f.pregunta, f.respuesta, f.activa
       FROM faq f JOIN categoria_faq c ON c.id = f.fk_categoria
       WHERE f.id = $1 AND f.activa = TRUE`,
      [positiveId(id)]
    );
    if (result.rowCount !== 1) throw httpError('Pregunta frecuente no encontrada', 404, 'FAQ_NOT_FOUND');
    return result.rows[0];
  }

  async function transact(adminId, action, entity, operation) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const { value, id } = await operation(client);
      await client.query(
        `INSERT INTO bitacora_administrativa
         (fk_admin, modulo, accion, entidad_afectada, id_entidad_afectada)
         VALUES ($1, 'FAQ', $2, $3, $4)`,
        [positiveId(adminId), action, entity, id]
      );
      await client.query('COMMIT');
      return value;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async function ensureCategory(client, id) {
    const result = await client.query('SELECT id FROM categoria_faq WHERE id = $1', [positiveId(id)]);
    if (result.rowCount !== 1) throw httpError('Categoría no encontrada', 404, 'FAQ_CATEGORY_NOT_FOUND');
  }

  async function ensureUniqueQuestion(client, categoryId, question, excludeId = null) {
    await client.query(
      'SELECT pg_advisory_xact_lock($1::int, hashtext(lower(btrim($2::text))))',
      [categoryId, question]
    );
    const values = excludeId === null ? [categoryId, question] : [categoryId, question, excludeId];
    const result = await client.query(
      `SELECT id FROM faq
       WHERE fk_categoria = $1 AND lower(btrim(pregunta)) = lower(btrim($2::text))
       ${excludeId === null ? '' : 'AND id <> $3'} LIMIT 1`,
      values
    );
    if (result.rowCount) {
      throw httpError(
        'Ya existe una pregunta frecuente igual en esta categoría.',
        409,
        'FAQ_DUPLICATE'
      );
    }
  }

  async function createFaq(data, adminId) {
    const categoryId = positiveId(data.categoriaId);
    const question = requiredText(data.pregunta, 'Pregunta');
    const answer = requiredText(data.respuesta, 'Respuesta');
    const active = data.activa === undefined ? true : data.activa;
    if (typeof active !== 'boolean') throw httpError('Estado inválido', 400, 'INVALID_FAQ_INPUT');
    return transact(adminId, 'CREAR', 'faq', async (client) => {
      await ensureCategory(client, categoryId);
      await ensureUniqueQuestion(client, categoryId, question);
      const result = await client.query(
        `INSERT INTO faq (fk_categoria, pregunta, respuesta, activa)
         VALUES ($1, $2, $3, $4) RETURNING id, fk_categoria, pregunta, respuesta, activa`,
        [categoryId, question, answer, active]
      );
      return { value: result.rows[0], id: result.rows[0].id };
    });
  }

  async function updateFaq(id, data, adminId) {
    const faqId = positiveId(id);
    const categoryId = positiveId(data.categoriaId);
    const question = requiredText(data.pregunta, 'Pregunta');
    const answer = requiredText(data.respuesta, 'Respuesta');
    if (typeof data.activa !== 'boolean') throw httpError('Estado inválido', 400, 'INVALID_FAQ_INPUT');
    return transact(adminId, 'EDITAR', 'faq', async (client) => {
      await ensureCategory(client, categoryId);
      const current = await client.query(
        `SELECT fk_categoria = $2 AND lower(btrim(pregunta)) = lower(btrim($3::text)) AS same_key
         FROM faq WHERE id = $1 FOR UPDATE`,
        [faqId, categoryId, question]
      );
      if (current.rowCount !== 1) {
        throw httpError('Pregunta frecuente no encontrada', 404, 'FAQ_NOT_FOUND');
      }
      if (!current.rows[0].same_key) {
        await ensureUniqueQuestion(client, categoryId, question, faqId);
      }
      const result = await client.query(
        `UPDATE faq SET fk_categoria = $1, pregunta = $2, respuesta = $3, activa = $4
         WHERE id = $5 RETURNING id, fk_categoria, pregunta, respuesta, activa`,
        [categoryId, question, answer, data.activa, faqId]
      );
      if (result.rowCount !== 1) throw httpError('Pregunta frecuente no encontrada', 404, 'FAQ_NOT_FOUND');
      return { value: result.rows[0], id: faqId };
    });
  }

  async function setFaqStatus(id, active, adminId) {
    const faqId = positiveId(id);
    if (typeof active !== 'boolean') throw httpError('Estado inválido', 400, 'INVALID_FAQ_INPUT');
    return transact(adminId, active ? 'ACTIVAR' : 'ARCHIVAR', 'faq', async (client) => {
      const result = await client.query(
        'UPDATE faq SET activa = $1 WHERE id = $2 RETURNING id, fk_categoria, pregunta, respuesta, activa',
        [active, faqId]
      );
      if (result.rowCount !== 1) throw httpError('Pregunta frecuente no encontrada', 404, 'FAQ_NOT_FOUND');
      return { value: result.rows[0], id: faqId };
    });
  }

  async function deleteFaq(id, adminId) {
    const faqId = positiveId(id);
    return transact(adminId, 'ELIMINAR', 'faq', async (client) => {
      const result = await client.query('DELETE FROM faq WHERE id = $1 RETURNING id', [faqId]);
      if (result.rowCount !== 1) throw httpError('Pregunta frecuente no encontrada', 404, 'FAQ_NOT_FOUND');
      return { value: { deleted: true, id: faqId }, id: faqId };
    });
  }

  async function createCategory(data, adminId) {
    const name = requiredText(data.nombre, 'Nombre', 100);
    const description = data.descripcion == null || String(data.descripcion).trim() === ''
      ? null : requiredText(data.descripcion, 'Descripción', 255);
    return transact(adminId, 'CREAR', 'categoria_faq', async (client) => {
      const result = await client.query(
        'INSERT INTO categoria_faq (nombre, descripcion) VALUES ($1, $2) RETURNING id, nombre, descripcion',
        [name, description]
      );
      return { value: result.rows[0], id: result.rows[0].id };
    });
  }

  async function updateCategory(id, data, adminId) {
    const categoryId = positiveId(id);
    const name = requiredText(data.nombre, 'Nombre', 100);
    const description = data.descripcion == null || String(data.descripcion).trim() === ''
      ? null : requiredText(data.descripcion, 'Descripción', 255);
    return transact(adminId, 'EDITAR', 'categoria_faq', async (client) => {
      const result = await client.query(
        'UPDATE categoria_faq SET nombre = $1, descripcion = $2 WHERE id = $3 RETURNING id, nombre, descripcion',
        [name, description, categoryId]
      );
      if (result.rowCount !== 1) throw httpError('Categoría no encontrada', 404, 'FAQ_CATEGORY_NOT_FOUND');
      return { value: result.rows[0], id: categoryId };
    });
  }

  async function deleteCategory(id, adminId) {
    const categoryId = positiveId(id);
    return transact(adminId, 'ELIMINAR', 'categoria_faq', async (client) => {
      const inUse = await client.query('SELECT 1 FROM faq WHERE fk_categoria = $1 LIMIT 1', [categoryId]);
      if (inUse.rowCount) throw httpError('La categoría tiene preguntas frecuentes asociadas', 409, 'FAQ_CATEGORY_IN_USE');
      const result = await client.query('DELETE FROM categoria_faq WHERE id = $1 RETURNING id', [categoryId]);
      if (result.rowCount !== 1) throw httpError('Categoría no encontrada', 404, 'FAQ_CATEGORY_NOT_FOUND');
      return { value: { deleted: true, id: categoryId }, id: categoryId };
    });
  }

  return { listCategories, listFaqs, getPublicFaq, createFaq, updateFaq,
    setFaqStatus, deleteFaq, createCategory, updateCategory, deleteCategory };
}

module.exports = { createFaqService, faqService: createFaqService(), httpError };
