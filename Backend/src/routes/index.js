const express = require('express');

/*
  Aquí importo las rutas principales del backend.
  Cada archivo de rutas agrupa las funcionalidades de un módulo específico
  para mantener el proyecto organizado.
*/
const authRoutes = require('../modules/auth/auth.routes');
const catalogosRoutes = require('../modules/catalogos/catalogos.routes');
const mascotasRoutes = require('../modules/pets/mascotas.routes');
const petsRoutes = require('../modules/pets/pets.routes');
const mapRoutes = require('../modules/map/map.routes');
const profileRoutes = require('../modules/profile/profile.routes');
const reportsRoutes = require('../modules/reports/reports.routes');

/*
  Rutas del módulo de preguntas frecuentes.
*/
const faqRoutes = require('../modules/faq/faq.routes');

/*
  Aquí creo el router principal de Express.

  Este router se conecta después en app.js bajo el prefijo /api.
*/
const router = express.Router();

/*
  Ruta de prueba para verificar que la API está funcionando.

  GET /api/health
*/
router.get('/health', (req, res) => {
  res.status(200).json({
    ok: true,
    message: 'API funcionando',
  });
});

/*
  ============================================================
  AUTENTICACIÓN
  ============================================================
*/

router.use('/auth', authRoutes);

/*
  ============================================================
  CATÁLOGOS
  ============================================================
*/

router.use('/catalogos', catalogosRoutes);

/*
  ============================================================
  MASCOTAS
  ============================================================
*/

router.use('/pets', mascotasRoutes);
router.use('/pets', petsRoutes);

/*
  ============================================================
  MAPA
  ============================================================
*/

router.use('/map', mapRoutes);

/*
  ============================================================
  PERFIL
  ============================================================
*/

router.use('/profile', profileRoutes);

/*
  ============================================================
  REPORTES
  ============================================================
*/

router.use('/reports', reportsRoutes);

/*
  ============================================================
  PREGUNTAS FRECUENTES
  ============================================================

  Todas las rutas de faq.routes.js estarán disponibles bajo:

  /api/faqs
*/

router.use('/faqs', faqRoutes);

/*
  Exporto el router principal para que app.js
  lo pueda montar bajo /api.
*/
module.exports = router;
