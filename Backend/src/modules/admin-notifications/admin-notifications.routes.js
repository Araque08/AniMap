
const express = require('express');

const authMiddleware = require(
  '../../middleware/auth.middleware'
);

const requireRole = require(
  '../../middleware/role.middleware'
);

const validateBody = require(
  '../../middleware/validate.middleware'
);

const {
  enviarNotificacionSchema
} = require('./admin-notifications.schemas');

const {
  listarAudiencias,
  enviarComunicado
} = require('./admin-notifications.controller');

const router = express.Router();

// =====================================================
// SEGURIDAD: SOLO ADMINISTRADORES
// =====================================================

router.use(
  authMiddleware,
  requireRole('ADMINISTRADOR')
);

// =====================================================
// VALIDAR FORMATO JSON
// =====================================================

function requireJson(req, res, next) {
  if (!req.is('application/json')) {
    return res.status(415).json({
      ok: false,
      message: 'Content-Type debe ser application/json'
    });
  }

  return next();
}

// =====================================================
// HU-049: CONSULTAR AUDIENCIAS
// =====================================================

// GET /api/admin/notifications/audiences
router.get(
  '/audiences',
  listarAudiencias
);

// =====================================================
// HU-049: REGISTRAR COMUNICADO ADMINISTRATIVO
// =====================================================

// POST /api/admin/notifications
router.post(
  '/',
  requireJson,
  validateBody(enviarNotificacionSchema),
  enviarComunicado
);

module.exports = router;
