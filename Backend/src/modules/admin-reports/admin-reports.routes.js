
const express = require('express');

const authMiddleware = require(
  '../../middleware/auth.middleware'
);

const requireRole = require(
  '../../middleware/role.middleware'
);

const controller = require(
  './admin-reports.controller'
);

const router = express.Router();

// ==========================================================
// SEGURIDAD: SOLO ADMINISTRADORES
// ==========================================================

router.use(
  authMiddleware,
  requireRole('ADMINISTRADOR')
);

// ==========================================================
// LISTAR Y BUSCAR TODOS LOS REPORTES
// ==========================================================

router.get(
  '/',
  controller.listReports
);


/*
  ============================================================
  DETECCIÓN DE POSIBLES REPORTES DUPLICADOS
  Solo disponible para administradores
  ============================================================
*/

router.get(
  '/duplicates',
  controller.getPossibleDuplicates
);


/*
  ============================================================
  HU-047: CONFIRMAR AVISTAMIENTO DUPLICADO
  ============================================================

  El administrador selecciona qué registro conservar.

  El backend realizará la eliminación lógica del duplicado,
  registrará la decisión y creará una notificación.
*/

router.post(
  '/duplicates/confirm',
  controller.confirmDuplicate
);



// ==========================================================
// OBTENER DETALLE DE UN REPORTE
// ==========================================================

router.get(
  '/:id',
  controller.getReport
);



/*
  ============================================================
  HU-076: ACTUALIZAR ESTADO DE REPORTE Y MASCOTA
  ============================================================
*/

router.patch(
  '/:id/status',
  controller.updateReportStatus
);


// ==========================================================
// EXPORTAR RUTAS
// ==========================================================

module.exports = router;

