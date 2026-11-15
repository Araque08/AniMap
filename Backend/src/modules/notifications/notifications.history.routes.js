
const express = require('express');

const authMiddleware = require('../../middleware/auth.middleware');

const {
  listarNotificaciones,
  marcarComoLeida
} = require('./notifications.history.controller');

const router = express.Router();

// =====================================================
// HU-070: CONSULTAR HISTORIAL DE NOTIFICACIONES
// =====================================================

router.get(
  '/',
  authMiddleware,
  listarNotificaciones
);

// =====================================================
// HU-071: MARCAR NOTIFICACIÓN COMO LEÍDA
// =====================================================

router.patch(
  '/:id/read',
  authMiddleware,
  marcarComoLeida
);

module.exports = router;
