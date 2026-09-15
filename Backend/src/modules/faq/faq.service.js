const db = require('../../config/postgres_db');

/*
  ============================================================
  UTILIDADES
  ============================================================
*/

function createHttpError(message, statusCode = 500) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function parsePositiveId(value, fieldName = 'id') {
  const id = Number(value);

  if (!Number.isInteger(id) || id <= 0) {
    throw createHttpError(
      `${fieldName} inválido`,
      400
    );
  }

  return id;
}

function normalizeRequiredText(value, fieldName) {
  const text = String(value ?? '').trim();

  if (!text) {
    throw createHttpError(
      `${fieldName} es obligatorio`,
      400
    );
  }

  return text;
}

function normalizeOptionalText(value) {
  if (value === null || value === undefined) {
    return null;
  }

  const text = String(value).trim();

  return text || null;
}

/*
  Registra las operaciones administrativas
  realizadas sobre las FAQ y sus categorías.
*/
async function registrarBitacora(
  client,
  {
    adminId,
    accion,
    entidadAfectada,
    idEntidadAfectada = null,
    motivo = null,
    detalle = null,
  }
) {
  await client.query(
    `
      INSERT INTO bitacora_administrativa (
        fk_admin,
        modulo,
        accion,
        entidad_afectada,
        id_entidad_afectada,
        motivo,
        detalle
      )
      VALUES (
        $1,
        'FAQ',
        $2,
        $3,
        $4,
        $5,
        $6
      )
    `,
    [
      adminId,
      accion,
      entidadAfectada,
      idEntidadAfectada,
      motivo,
      detalle,
    ]
  );
}

/*
  ============================================================
  CONSULTA DE CATEGORÍAS
  ============================================================
*/

/*
  Devuelve todas las categorías FAQ.

  Esta operación puede ser utilizada tanto por la aplicación
  normal como por el panel administrativo.
*/
async function listarCategorias() {
  const result = await db.pool.query(
    `
      SELECT
        c.id,
        c.nombre,
        c.descripcion,
        COUNT(f.id)::INT AS total_faq,
        COUNT(f.id) FILTER (
          WHERE f.activa = TRUE
        )::INT AS total_activas

      FROM categoria_faq c

      LEFT JOIN faq f
        ON f.fk_categoria = c.id

      GROUP BY
        c.id,
        c.nombre,
        c.descripcion

      ORDER BY
        c.nombre ASC
    `
  );

  return result.rows;
}

/*
  ============================================================
  CONSULTA DE FAQ
  ============================================================
*/

/*
  Consulta las preguntas frecuentes.

  Parámetros opcionales:

  categoriaId
  search
  includeInactive

  Para usuarios normales:
  includeInactive = false

  Para administración:
  includeInactive = true
*/
async function listarFaqs({
  categoriaId = null,
  search = null,
  includeInactive = false,
} = {}) {
  const values = [];

  const conditions = [];

  if (!includeInactive) {
    conditions.push('f.activa = TRUE');
  }

  if (
    categoriaId !== null &&
    categoriaId !== undefined &&
    categoriaId !== ''
  ) {
    const id = parsePositiveId(
      categoriaId,
      'categoriaId'
    );

    values.push(id);

    conditions.push(
      `f.fk_categoria = $${values.length}`
    );
  }

  if (
    search !== null &&
    search !== undefined &&
    String(search).trim() !== ''
  ) {
    values.push(
      `%${String(search).trim()}%`
    );

    conditions.push(
      `(
        f.pregunta ILIKE $${values.length}
        OR
        f.respuesta ILIKE $${values.length}
      )`
    );
  }

  const where =
    conditions.length > 0
      ? `WHERE ${conditions.join(' AND ')}`
      : '';

  const result = await db.pool.query(
    `
      SELECT
        f.id,
        f.fk_categoria,
        c.nombre AS categoria,
        f.pregunta,
        f.respuesta,
        f.activa

      FROM faq f

      INNER JOIN categoria_faq c
        ON c.id = f.fk_categoria

      ${where}

      ORDER BY
        c.nombre ASC,
        f.id DESC
    `,
    values
  );

  return result.rows;
}

/*
  Consulta una FAQ específica.
*/
async function obtenerFaqPorId(id) {
  const faqId = parsePositiveId(id);

  const result = await db.pool.query(
    `
      SELECT
        f.id,
        f.fk_categoria,
        c.nombre AS categoria,
        f.pregunta,
        f.respuesta,
        f.activa

      FROM faq f

      INNER JOIN categoria_faq c
        ON c.id = f.fk_categoria

      WHERE f.id = $1

      LIMIT 1
    `,
    [
      faqId,
    ]
  );

  if (result.rowCount === 0) {
    throw createHttpError(
      'Pregunta frecuente no encontrada',
      404
    );
  }

  return result.rows[0];
}

/*
  ============================================================
  CREAR FAQ
  ============================================================
*/

async function crearFaq({
  categoriaId,
  pregunta,
  respuesta,
  activa = true,
  adminId,
}) {
  const categoryId = parsePositiveId(
    categoriaId,
    'categoriaId'
  );

  const adminUserId = parsePositiveId(
    adminId,
    'adminId'
  );

  const preguntaNormalizada =
    normalizeRequiredText(
      pregunta,
      'La pregunta'
    );

  const respuestaNormalizada =
    normalizeRequiredText(
      respuesta,
      'La respuesta'
    );

  if (typeof activa !== 'boolean') {
    throw createHttpError(
      'El estado activa debe ser verdadero o falso',
      400
    );
  }

  const client =
    await db.pool.connect();

  try {
    await client.query('BEGIN');

    /*
      Comprobamos que la categoría exista.
    */
    const categoriaResult =
      await client.query(
        `
          SELECT
            id,
            nombre

          FROM categoria_faq

          WHERE id = $1

          LIMIT 1
        `,
        [
          categoryId,
        ]
      );

    if (categoriaResult.rowCount === 0) {
      throw createHttpError(
        'La categoría seleccionada no existe',
        404
      );
    }

    /*
      Evitamos registrar exactamente la misma pregunta
      dentro de la misma categoría.
    */
    const duplicateResult =
      await client.query(
        `
          SELECT id

          FROM faq

          WHERE
            fk_categoria = $1
            AND LOWER(TRIM(pregunta))
                = LOWER(TRIM($2))

          LIMIT 1
        `,
        [
          categoryId,
          preguntaNormalizada,
        ]
      );

    if (duplicateResult.rowCount > 0) {
      throw createHttpError(
        'Ya existe una pregunta igual en esta categoría',
        409
      );
    }

    const result =
      await client.query(
        `
          INSERT INTO faq (
            fk_categoria,
            pregunta,
            respuesta,
            activa
          )
          VALUES (
            $1,
            $2,
            $3,
            $4
          )

          RETURNING
            id,
            fk_categoria,
            pregunta,
            respuesta,
            activa
        `,
        [
          categoryId,
          preguntaNormalizada,
          respuestaNormalizada,
          activa,
        ]
      );

    const nuevaFaq =
      result.rows[0];

    await registrarBitacora(
      client,
      {
        adminId: adminUserId,
        accion: 'CREAR',
        entidadAfectada: 'FAQ',
        idEntidadAfectada: nuevaFaq.id,
        detalle:
          `Se creó la pregunta frecuente: ${preguntaNormalizada}`,
      }
    );

    await client.query('COMMIT');

    return {
      ...nuevaFaq,
      categoria:
        categoriaResult.rows[0].nombre,
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/*
  ============================================================
  EDITAR FAQ
  ============================================================
*/

async function editarFaq(
  id,
  {
    categoriaId,
    pregunta,
    respuesta,
    activa,
    adminId,
  }
) {
  const faqId =
    parsePositiveId(id);

  const categoryId =
    parsePositiveId(
      categoriaId,
      'categoriaId'
    );

  const adminUserId =
    parsePositiveId(
      adminId,
      'adminId'
    );

  const preguntaNormalizada =
    normalizeRequiredText(
      pregunta,
      'La pregunta'
    );

  const respuestaNormalizada =
    normalizeRequiredText(
      respuesta,
      'La respuesta'
    );

  if (typeof activa !== 'boolean') {
    throw createHttpError(
      'El estado activa debe ser verdadero o falso',
      400
    );
  }

  const client =
    await db.pool.connect();

  try {
    await client.query('BEGIN');

    const faqActualResult =
      await client.query(
        `
          SELECT id

          FROM faq

          WHERE id = $1

          LIMIT 1
        `,
        [
          faqId,
        ]
      );

    if (faqActualResult.rowCount === 0) {
      throw createHttpError(
        'Pregunta frecuente no encontrada',
        404
      );
    }

    const categoriaResult =
      await client.query(
        `
          SELECT
            id,
            nombre

          FROM categoria_faq

          WHERE id = $1

          LIMIT 1
        `,
        [
          categoryId,
        ]
      );

    if (categoriaResult.rowCount === 0) {
      throw createHttpError(
        'La categoría seleccionada no existe',
        404
      );
    }

    const duplicateResult =
      await client.query(
        `
          SELECT id

          FROM faq

          WHERE
            fk_categoria = $1
            AND LOWER(TRIM(pregunta))
                = LOWER(TRIM($2))
            AND id <> $3

          LIMIT 1
        `,
        [
          categoryId,
          preguntaNormalizada,
          faqId,
        ]
      );

    if (duplicateResult.rowCount > 0) {
      throw createHttpError(
        'Ya existe una pregunta igual en esta categoría',
        409
      );
    }

    const result =
      await client.query(
        `
          UPDATE faq

          SET
            fk_categoria = $1,
            pregunta = $2,
            respuesta = $3,
            activa = $4

          WHERE id = $5

          RETURNING
            id,
            fk_categoria,
            pregunta,
            respuesta,
            activa
        `,
        [
          categoryId,
          preguntaNormalizada,
          respuestaNormalizada,
          activa,
          faqId,
        ]
      );

    await registrarBitacora(
      client,
      {
        adminId: adminUserId,
        accion: 'EDITAR',
        entidadAfectada: 'FAQ',
        idEntidadAfectada: faqId,
        detalle:
          `Se actualizó la pregunta frecuente: ${preguntaNormalizada}`,
      }
    );

    await client.query('COMMIT');

    return {
      ...result.rows[0],
      categoria:
        categoriaResult.rows[0].nombre,
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/*
  ============================================================
  ACTIVAR / ARCHIVAR FAQ
  ============================================================
*/

async function cambiarEstadoFaq(
  id,
  {
    activa,
    adminId,
  }
) {
  const faqId =
    parsePositiveId(id);

  const adminUserId =
    parsePositiveId(
      adminId,
      'adminId'
    );

  if (typeof activa !== 'boolean') {
    throw createHttpError(
      'El campo activa debe ser verdadero o falso',
      400
    );
  }

  const client =
    await db.pool.connect();

  try {
    await client.query('BEGIN');

    const result =
      await client.query(
        `
          UPDATE faq

          SET
            activa = $1

          WHERE id = $2

          RETURNING
            id,
            fk_categoria,
            pregunta,
            respuesta,
            activa
        `,
        [
          activa,
          faqId,
        ]
      );

    if (result.rowCount === 0) {
      throw createHttpError(
        'Pregunta frecuente no encontrada',
        404
      );
    }

    await registrarBitacora(
      client,
      {
        adminId: adminUserId,
        accion:
          activa
            ? 'ACTIVAR'
            : 'ARCHIVAR',
        entidadAfectada: 'FAQ',
        idEntidadAfectada: faqId,
        detalle:
          activa
            ? 'Se activó la pregunta frecuente'
            : 'Se archivó la pregunta frecuente',
      }
    );

    await client.query('COMMIT');

    return result.rows[0];
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/*
  ============================================================
  CREAR CATEGORÍA
  ============================================================
*/

async function crearCategoria({
  nombre,
  descripcion = null,
  adminId,
}) {
  const adminUserId =
    parsePositiveId(
      adminId,
      'adminId'
    );

  const nombreNormalizado =
    normalizeRequiredText(
      nombre,
      'El nombre'
    );

  const descripcionNormalizada =
    normalizeOptionalText(
      descripcion
    );

  const client =
    await db.pool.connect();

  try {
    await client.query('BEGIN');

    const duplicateResult =
      await client.query(
        `
          SELECT id

          FROM categoria_faq

          WHERE
            LOWER(TRIM(nombre))
              = LOWER(TRIM($1))

          LIMIT 1
        `,
        [
          nombreNormalizado,
        ]
      );

    if (duplicateResult.rowCount > 0) {
      throw createHttpError(
        'Ya existe una categoría con ese nombre',
        409
      );
    }

    const result =
      await client.query(
        `
          INSERT INTO categoria_faq (
            nombre,
            descripcion
          )
          VALUES (
            $1,
            $2
          )

          RETURNING
            id,
            nombre,
            descripcion
        `,
        [
          nombreNormalizado,
          descripcionNormalizada,
        ]
      );

    const categoria =
      result.rows[0];

    await registrarBitacora(
      client,
      {
        adminId: adminUserId,
        accion: 'CREAR',
        entidadAfectada:
          'CATEGORIA_FAQ',
        idEntidadAfectada:
          categoria.id,
        detalle:
          `Se creó la categoría FAQ: ${categoria.nombre}`,
      }
    );

    await client.query('COMMIT');

    return categoria;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/*
  ============================================================
  EDITAR CATEGORÍA
  ============================================================
*/

async function editarCategoria(
  id,
  {
    nombre,
    descripcion = null,
    adminId,
  }
) {
  const categoriaId =
    parsePositiveId(id);

  const adminUserId =
    parsePositiveId(
      adminId,
      'adminId'
    );

  const nombreNormalizado =
    normalizeRequiredText(
      nombre,
      'El nombre'
    );

  const descripcionNormalizada =
    normalizeOptionalText(
      descripcion
    );

  const client =
    await db.pool.connect();

  try {
    await client.query('BEGIN');

    const duplicateResult =
      await client.query(
        `
          SELECT id

          FROM categoria_faq

          WHERE
            LOWER(TRIM(nombre))
              = LOWER(TRIM($1))
            AND id <> $2

          LIMIT 1
        `,
        [
          nombreNormalizado,
          categoriaId,
        ]
      );

    if (duplicateResult.rowCount > 0) {
      throw createHttpError(
        'Ya existe una categoría con ese nombre',
        409
      );
    }

    const result =
      await client.query(
        `
          UPDATE categoria_faq

          SET
            nombre = $1,
            descripcion = $2

          WHERE id = $3

          RETURNING
            id,
            nombre,
            descripcion
        `,
        [
          nombreNormalizado,
          descripcionNormalizada,
          categoriaId,
        ]
      );

    if (result.rowCount === 0) {
      throw createHttpError(
        'Categoría no encontrada',
        404
      );
    }

    await registrarBitacora(
      client,
      {
        adminId: adminUserId,
        accion: 'EDITAR',
        entidadAfectada:
          'CATEGORIA_FAQ',
        idEntidadAfectada:
          categoriaId,
        detalle:
          `Se actualizó la categoría FAQ: ${nombreNormalizado}`,
      }
    );

    await client.query('COMMIT');

    return result.rows[0];
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/*
  ============================================================
  ELIMINAR CATEGORÍA
  ============================================================

  La base de datos utiliza ON DELETE RESTRICT.

  Por lo tanto, una categoría que tenga preguntas asociadas
  NO puede eliminarse.

  Esto evita dejar FAQ sin categoría.
*/
async function eliminarCategoria(
  id,
  {
    adminId,
  }
) {
  const categoriaId =
    parsePositiveId(id);

  const adminUserId =
    parsePositiveId(
      adminId,
      'adminId'
    );

  const client =
    await db.pool.connect();

  try {
    await client.query('BEGIN');

    const categoriaResult =
      await client.query(
        `
          SELECT
            id,
            nombre

          FROM categoria_faq

          WHERE id = $1

          LIMIT 1
        `,
        [
          categoriaId,
        ]
      );

    if (categoriaResult.rowCount === 0) {
      throw createHttpError(
        'Categoría no encontrada',
        404
      );
    }

    const faqResult =
      await client.query(
        `
          SELECT COUNT(*)::INT AS total

          FROM faq

          WHERE fk_categoria = $1
        `,
        [
          categoriaId,
        ]
      );

    const totalFaq =
      faqResult.rows[0].total;

    if (totalFaq > 0) {
      throw createHttpError(
        'No se puede eliminar la categoría porque tiene preguntas frecuentes asociadas',
        409
      );
    }

    await client.query(
      `
        DELETE FROM categoria_faq

        WHERE id = $1
      `,
      [
        categoriaId,
      ]
    );

    await registrarBitacora(
      client,
      {
        adminId: adminUserId,
        accion: 'ELIMINAR',
        entidadAfectada:
          'CATEGORIA_FAQ',
        idEntidadAfectada:
          categoriaId,
        detalle:
          `Se eliminó la categoría FAQ: ${categoriaResult.rows[0].nombre}`,
      }
    );

    await client.query('COMMIT');

    return {
      id: categoriaId,
      nombre:
        categoriaResult.rows[0].nombre,
      eliminada: true,
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/*
  ============================================================
  EXPORTACIONES
  ============================================================
*/

module.exports = {
  listarCategorias,
  listarFaqs,
  obtenerFaqPorId,
  crearFaq,
  editarFaq,
  cambiarEstadoFaq,
  crearCategoria,
  editarCategoria,
  eliminarCategoria,
};