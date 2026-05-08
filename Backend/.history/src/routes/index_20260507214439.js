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

/*
  Aquí importo las rutas del módulo del mapa.
  Este módulo será el encargado de entregar al frontend los datos que necesita
  para pintar mascotas perdidas, avistamientos y mascotas encontradas.
*/
const mapRoutes = require('../modules/map/map.routes');

/*
  Aquí creo el router principal de Express.
  Este router se conecta después en app.js bajo el prefijo /api.
  Por eso, cualquier ruta definida aquí realmente queda disponible como /api/...
*/
const router = express.Router();

/*
  Ruta de prueba para verificar que la API está funcionando.
  la podemos consultar desde el navegador en:
  http://localhost:3000/api/health
*/
router.get('/health', (req, res) => {
  res.status(200).json({
    ok: true,
    message: 'API funcionando',
  });
});

/*
  Aquí conecto el módulo de autenticación.
  Todas las rutas internas de auth.routes.js quedan bajo:
  /api/auth
*/
router.use('/auth', authRoutes);

/*
  Aquí conecto el módulo de catálogos.
  Sirve para consultar datos base como especies, razas u otros listados
  necesarios para formularios de la aplicación.
*/
router.use('/catalogos', catalogosRoutes);

/*
  Aquí conecto las rutas de mascotas.
  En el proyecto existen dos archivos de rutas relacionados con mascotas.
  */
router.use('/pets', mascotasRoutes);
router.use('/pets', petsRoutes);

/*
  Aquí conecto el nuevo módulo del mapa.
  Con esta línea, la ruta definida en map.routes.js como /reports queda
  disponible finalmente como:
  http://localhost:3000/api/map/reports
*/
router.use('/map', mapRoutes);

/*
  Exporto el router principal para que app.js lo pueda montar en /api.
*/
module.exports = router;
