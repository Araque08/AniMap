const express = require('express');
const rateLimit = require('express-rate-limit');

const validateBody = require('../../middleware/validate.middleware');
const authMiddleware = require('../../middleware/auth.middleware');

const authController = require('./auth.controller');

const {
  registerSchema,
  loginSchema,
  refreshSchema,
  logoutSchema,
  verifyAccountSchema,
  resendVerificationCodeSchema,
  forgotPasswordSchema,
  resetPasswordSchema,
} = require('./auth.schemas');

const router = express.Router();

const limiterOptions = {
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
};

const loginLimiter = rateLimit({
  ...limiterOptions,
  skipSuccessfulRequests: true,
  message: {
    ok: false,
    message: 'Demasiados intentos de inicio de sesión. Intenta nuevamente en unos minutos.',
  },
});

function sensitiveLimiter() {
  return rateLimit({
    ...limiterOptions,
    message: { ok: false, message: 'Demasiados intentos. Intenta más tarde.' },
  });
}

const registerLimiter = sensitiveLimiter();
const verifyLimiter = sensitiveLimiter();
const resendLimiter = sensitiveLimiter();
const forgotLimiter = sensitiveLimiter();
const resetLimiter = sensitiveLimiter();


/*
  Aquí hicimos un middleware para exigir que las peticiones
  lleguen en formato JSON.

  Esto evita procesar datos enviados con un formato incorrecto.
*/
function requireJson(req, res, next) {

  if (!req.is('application/json')) {

    return res.status(415).json({
      ok: false,
      message: 'Content-Type debe ser application/json',
    });

  }

  next();
}


/*
  ============================================================
  REGISTRO
  ============================================================
*/

router.post(
  '/register',
  registerLimiter,
  requireJson,
  validateBody(registerSchema),
  authController.register
);


/*
  ============================================================
  INICIO DE SESIÓN
  ============================================================
*/

router.post(
  '/login',
  loginLimiter,
  requireJson,
  validateBody(loginSchema),
  authController.login
);

router.post(
  '/refresh',
  requireJson,
  validateBody(refreshSchema),
  authController.refresh
);

router.post(
  '/logout',
  requireJson,
  validateBody(logoutSchema),
  authController.logout
);

router.get('/sessions', authMiddleware, authController.listSessions);
router.post(
  '/sessions/:id/revoke',
  authMiddleware,
  authController.revokeSession
);


/*
  ============================================================
  VERIFICACIÓN DE CUENTA
  ============================================================
*/

router.post(
  '/verify-account',
  verifyLimiter,
  requireJson,
  validateBody(verifyAccountSchema),
  authController.verifyAccount
);


/*
  ============================================================
  REENVÍO DE CÓDIGO DE VERIFICACIÓN
  ============================================================
*/

router.post(
  '/resend-verification-code',
  resendLimiter,
  requireJson,
  validateBody(resendVerificationCodeSchema),
  authController.resendVerificationCode
);


/*
  ============================================================
  RECUPERACIÓN DE CONTRASEÑA
  ============================================================
*/


/*
  Primera etapa:

  El usuario envía su correo.

  Si la cuenta existe y está activa, el servicio genera
  un código temporal y lo envía por correo.
*/
router.post(
  '/forgot-password',
  forgotLimiter,
  requireJson,
  validateBody(forgotPasswordSchema),
  authController.forgotPassword
);


/*
  Segunda etapa:

  El usuario envía:

  - correo
  - código de recuperación
  - nueva contraseña
  - confirmación de contraseña

  Si todo es válido, se reemplaza la contraseña anterior.
*/
router.post(
  '/reset-password',
  resetLimiter,
  requireJson,
  validateBody(resetPasswordSchema),
  authController.resetPassword
);


/*
  Aquí exportamos el router para que app.js
  pueda usar estas rutas dentro de /api/auth.
*/
module.exports = router;
