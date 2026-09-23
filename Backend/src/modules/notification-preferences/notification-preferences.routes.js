const express = require('express');
const authMiddleware = require('../../middleware/auth.middleware');
const validateBody = require('../../middleware/validate.middleware');
const controller = require('./notification-preferences.controller');
const {
  notificationPreferencesSchema,
} = require('./notification-preferences.schemas');

const router = express.Router();

function requireJson(req, res, next) {
  if (!req.is('application/json')) {
    return res.status(415).json({
      ok: false,
      message: 'Content-Type debe ser application/json',
    });
  }
  return next();
}

router.get('/', authMiddleware, controller.getPreferences);
router.patch(
  '/',
  authMiddleware,
  requireJson,
  validateBody(notificationPreferencesSchema),
  controller.updatePreferences
);

module.exports = router;
