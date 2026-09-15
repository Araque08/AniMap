const faqService = require('./faq.service');

/*
  ============================================================
  LISTAR FAQ PÚBLICAS
  ============================================================

  GET /api/faqs

  Permite consultar las preguntas activas.

  Query params opcionales:

  ?categoriaId=1
  ?search=mascota
*/
async function listarFaqsPublicas(req, res, next) {
  try {
    const faqs = await faqService.listarFaqs({
      categoriaId: req.query.categoriaId,
      search: req.query.search,
      includeInactive: false,
    });

    return res.status(200).json({
      ok: true,
      message: 'Preguntas frecuentes consultadas correctamente',
      data: faqs,
    });
  } catch (error) {
    return next(error);
  }
}

/*
  ============================================================
  LISTAR TODAS LAS FAQ - ADMINISTRADOR
  ============================================================

  GET /api/faqs/admin

  Incluye:

  - FAQ activas
  - FAQ archivadas
*/
async function listarFaqsAdmin(req, res, next) {
  try {
    const faqs = await faqService.listarFaqs({
      categoriaId: req.query.categoriaId,
      search: req.query.search,
      includeInactive: true,
    });

    return res.status(200).json({
      ok: true,
      message: 'Preguntas frecuentes administrativas consultadas correctamente',
      data: faqs,
    });
  } catch (error) {
    return next(error);
  }
}

/*
  ============================================================
  OBTENER FAQ POR ID
  ============================================================

  GET /api/faqs/:id
*/
async function obtenerFaqPorId(req, res, next) {
  try {
    const faq =
      await faqService.obtenerFaqPorId(
        req.params.id
      );

    return res.status(200).json({
      ok: true,
      message: 'Pregunta frecuente consultada correctamente',
      data: faq,
    });
  } catch (error) {
    return next(error);
  }
}

/*
  ============================================================
  LISTAR CATEGORÍAS
  ============================================================

  GET /api/faqs/categories

  Las categorías se necesitan tanto en la aplicación
  normal como en el panel administrativo.
*/
async function listarCategorias(req, res, next) {
  try {
    const categorias =
      await faqService.listarCategorias();

    return res.status(200).json({
      ok: true,
      message: 'Categorías FAQ consultadas correctamente',
      data: categorias,
    });
  } catch (error) {
    return next(error);
  }
}

/*
  ============================================================
  CREAR FAQ
  ============================================================

  POST /api/faqs

  Solo ADMINISTRADOR.

  Body:

  {
    "categoriaId": 1,
    "pregunta": "¿Cómo reporto una mascota perdida?",
    "respuesta": "Ingresa a la opción...",
    "activa": true
  }
*/
async function crearFaq(req, res, next) {
  try {
    const faq =
      await faqService.crearFaq({
        categoriaId:
          req.body.categoriaId,

        pregunta:
          req.body.pregunta,

        respuesta:
          req.body.respuesta,

        activa:
          req.body.activa ?? true,

        /*
          El ID NO viene desde Flutter.

          Se obtiene directamente del token
          autenticado.
        */
        adminId:
          req.auth.userId,
      });

    return res.status(201).json({
      ok: true,
      message: 'Pregunta frecuente creada correctamente',
      data: faq,
    });
  } catch (error) {
    return next(error);
  }
}

/*
  ============================================================
  EDITAR FAQ
  ============================================================

  PUT /api/faqs/:id

  Solo ADMINISTRADOR.

  Body:

  {
    "categoriaId": 1,
    "pregunta": "...",
    "respuesta": "...",
    "activa": true
  }
*/
async function editarFaq(req, res, next) {
  try {
    const faq =
      await faqService.editarFaq(
        req.params.id,
        {
          categoriaId:
            req.body.categoriaId,

          pregunta:
            req.body.pregunta,

          respuesta:
            req.body.respuesta,

          activa:
            req.body.activa,

          adminId:
            req.auth.userId,
        }
      );

    return res.status(200).json({
      ok: true,
      message: 'Pregunta frecuente actualizada correctamente',
      data: faq,
    });
  } catch (error) {
    return next(error);
  }
}

/*
  ============================================================
  ACTIVAR / ARCHIVAR FAQ
  ============================================================

  PATCH /api/faqs/:id/status

  Solo ADMINISTRADOR.

  Body:

  {
    "activa": false
  }

  false = archivada
  true  = activa
*/
async function cambiarEstadoFaq(
  req,
  res,
  next
) {
  try {
    const faq =
      await faqService.cambiarEstadoFaq(
        req.params.id,
        {
          activa:
            req.body.activa,

          adminId:
            req.auth.userId,
        }
      );

    return res.status(200).json({
      ok: true,
      message:
        faq.activa
          ? 'Pregunta frecuente activada correctamente'
          : 'Pregunta frecuente archivada correctamente',
      data: faq,
    });
  } catch (error) {
    return next(error);
  }
}

/*
  ============================================================
  CREAR CATEGORÍA
  ============================================================

  POST /api/faqs/categories

  Solo ADMINISTRADOR.

  Body:

  {
    "nombre": "Reportes",
    "descripcion": "Preguntas sobre reportes de mascotas"
  }
*/
async function crearCategoria(
  req,
  res,
  next
) {
  try {
    const categoria =
      await faqService.crearCategoria({
        nombre:
          req.body.nombre,

        descripcion:
          req.body.descripcion,

        adminId:
          req.auth.userId,
      });

    return res.status(201).json({
      ok: true,
      message: 'Categoría FAQ creada correctamente',
      data: categoria,
    });
  } catch (error) {
    return next(error);
  }
}

/*
  ============================================================
  EDITAR CATEGORÍA
  ============================================================

  PUT /api/faqs/categories/:id

  Solo ADMINISTRADOR.
*/
async function editarCategoria(
  req,
  res,
  next
) {
  try {
    const categoria =
      await faqService.editarCategoria(
        req.params.id,
        {
          nombre:
            req.body.nombre,

          descripcion:
            req.body.descripcion,

          adminId:
            req.auth.userId,
        }
      );

    return res.status(200).json({
      ok: true,
      message: 'Categoría FAQ actualizada correctamente',
      data: categoria,
    });
  } catch (error) {
    return next(error);
  }
}

/*
  ============================================================
  ELIMINAR CATEGORÍA
  ============================================================

  DELETE /api/faqs/categories/:id

  Solo ADMINISTRADOR.

  Solo se puede eliminar cuando no tenga
  preguntas frecuentes asociadas.
*/
async function eliminarCategoria(
  req,
  res,
  next
) {
  try {
    const resultado =
      await faqService.eliminarCategoria(
        req.params.id,
        {
          adminId:
            req.auth.userId,
        }
      );

    return res.status(200).json({
      ok: true,
      message: 'Categoría FAQ eliminada correctamente',
      data: resultado,
    });
  } catch (error) {
    return next(error);
  }
}

/*
  ============================================================
  EXPORTACIONES
  ============================================================
*/

module.exports = {
  listarFaqsPublicas,
  listarFaqsAdmin,
  obtenerFaqPorId,
  listarCategorias,
  crearFaq,
  editarFaq,
  cambiarEstadoFaq,
  crearCategoria,
  editarCategoria,
  eliminarCategoria,
};