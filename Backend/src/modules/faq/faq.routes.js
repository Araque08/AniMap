const express = require('express');

const faqController = require('./faq.controller');

const authMiddleware = require('../../middleware/auth.middleware');
const requireRole = require('../../middleware/role.middleware');

const router = express.Router();

/*
  ============================================================
  RUTAS PÚBLICAS
  ============================================================

  Estas rutas permiten consultar la información de ayuda
  disponible en AniMap.

  No requieren autenticación.
*/

/*
  GET /api/faqs

  Lista únicamente las preguntas frecuentes activas.

  También permite:

  /api/faqs?categoriaId=1
  /api/faqs?search=mascota
*/
router.get(
  '/',
  faqController.listarFaqsPublicas
);

/*
  GET /api/faqs/categories

  Lista las categorías disponibles.
*/
router.get(
  '/categories',
  faqController.listarCategorias
);

/*
  ============================================================
  RUTAS ADMINISTRATIVAS
  ============================================================

  Todas estas rutas requieren:

  1. Token de acceso válido.
  2. Rol ADMINISTRADOR.
*/

/*
  GET /api/faqs/admin

  Permite al administrador consultar tanto
  preguntas activas como archivadas.
*/
router.get(
  '/admin',
  authMiddleware,
  requireRole('ADMINISTRADOR'),
  faqController.listarFaqsAdmin
);

/*
  ============================================================
  ADMINISTRACIÓN DE CATEGORÍAS
  ============================================================
*/

/*
  POST /api/faqs/categories

  Crear categoría.
*/
router.post(
  '/categories',
  authMiddleware,
  requireRole('ADMINISTRADOR'),
  faqController.crearCategoria
);

/*
  PUT /api/faqs/categories/:id

  Editar categoría.
*/
router.put(
  '/categories/:id',
  authMiddleware,
  requireRole('ADMINISTRADOR'),
  faqController.editarCategoria
);

/*
  DELETE /api/faqs/categories/:id

  Eliminar categoría.

  Solo será posible cuando la categoría
  no tenga FAQ relacionadas.
*/
router.delete(
  '/categories/:id',
  authMiddleware,
  requireRole('ADMINISTRADOR'),
  faqController.eliminarCategoria
);

/*
  ============================================================
  ADMINISTRACIÓN DE FAQ
  ============================================================
*/

/*
  POST /api/faqs

  Crear una nueva pregunta frecuente.
*/
router.post(
  '/',
  authMiddleware,
  requireRole('ADMINISTRADOR'),
  faqController.crearFaq
);

/*
  PUT /api/faqs/:id

  Editar una pregunta frecuente.
*/
router.put(
  '/:id',
  authMiddleware,
  requireRole('ADMINISTRADOR'),
  faqController.editarFaq
);

/*
  PATCH /api/faqs/:id/status

  Activar o archivar una pregunta frecuente.
*/
router.patch(
  '/:id/status',
  authMiddleware,
  requireRole('ADMINISTRADOR'),
  faqController.cambiarEstadoFaq
);

/*
  ============================================================
  CONSULTA INDIVIDUAL
  ============================================================

  IMPORTANTE:
  Esta ruta queda después de /admin y /categories
  para que Express no interprete esas palabras como un :id.
*/

/*
  GET /api/faqs/:id
*/
router.get(
  '/:id',
  faqController.obtenerFaqPorId
);

module.exports = router;