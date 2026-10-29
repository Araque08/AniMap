
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

