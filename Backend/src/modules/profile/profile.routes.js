const express = require('express');
const authMiddleware = require('../../middleware/auth.middleware');
const validateBody = require('../../middleware/validate.middleware');
const profileController = require('./profile.controller');
const { updateProfileSchema } = require('./profile.schemas');

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

router.get('/', authMiddleware, profileController.getProfile);

router.patch(
  '/',
  authMiddleware,
  requireJson,
  validateBody(updateProfileSchema),
  profileController.updateProfile
);

module.exports = router;
