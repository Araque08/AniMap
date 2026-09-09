const express = require('express');

const validateBody = require('../../middleware/validate.middleware');

const authController = require('./auth.controller');

const {
  registerSchema,
  loginSchema,
  verifyAccountSchema,
  resendVerificationCodeSchema,
  forgotPasswordSchema,
  resetPasswordSchema,
} = require('./auth.schemas');

const router = express.Router();


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
  requireJson,
  validateBody(loginSchema),
  authController.login
);


/*
  ============================================================
  VERIFICACIÓN DE CUENTA
  ============================================================
*/

router.post(
  '/verify-account',
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
  requireJson,
  validateBody(resetPasswordSchema),
  authController.resetPassword
);


/*
  Aquí exportamos el router para que app.js
  pueda usar estas rutas dentro de /api/auth.
*/
module.exports = router;