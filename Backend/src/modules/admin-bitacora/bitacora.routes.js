
const express = require('express');

const authMiddleware = require(
  '../../middleware/auth.middleware'
);

const requireRole = require(
  '../../middleware/role.middleware'
);

const controller = require('./bitacora.controller');

const router = express.Router();

/*
  Todas las rutas de bitácora requieren:
  1. Sesión autenticada y activa.
  2. Rol ADMINISTRADOR.
*/
router.use(
  authMiddleware,
  requireRole('ADMINISTRADOR')
);

/*
  GET /api/admin/bitacora

  Permite consultar el historial y aplicar filtros.
*/
router.get(
  '/',
  controller.listarBitacora
);

module.exports = router;
