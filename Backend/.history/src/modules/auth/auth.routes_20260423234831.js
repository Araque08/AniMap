const express = require('express');
const validateBody = require('../../middleware/validate.middleware');
const authController = require('./auth.controller');
const {
  registerSchema,
  loginSchema,
  verifyAccountSchema,
  resendVerificationCodeSchema,
} = require('./auth.schemas');

const router = express.Router();

function requireJson(req, res, next) {
  if (!req.is('application/json')) {
    return res.status(415).json({
      ok: false,
      message: 'Content-Type debe ser application/json',
    });
  }

  next();
}

router.post('/register', requireJson, validateBody(registerSchema), authController.register);
router.post('/login', requireJson, validateBody(loginSchema), authController.login);
router.post('/verify-account', requireJson, validateBody(verifyAccountSchema), authController.verifyAccount);
router.post('/resend-verification-code', requireJson, validateBody(resendVerificationCodeSchema), authController.resendVerificationCode);

module.exports = router;