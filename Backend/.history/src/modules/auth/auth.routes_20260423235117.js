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

/*
  Aquí hicimos un middleware para exigir que las peticiones lleguen en JSON.
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
  Aquí definimos la ruta de registro.
  Primero validamos que llegue JSON, luego validamos el cuerpo con registerSchema,
  y finalmente enviamos la petición al controlador.
*/
router.post(
  '/register',
  requireJson,
  validateBody(registerSchema),
  authController.register
);

/*
  Aquí definimos la ruta de inicio de sesión.
  Validamos los datos antes de intentar autenticar al usuario.
*/
router.post(
  '/login',
  requireJson,
  validateBody(loginSchema),
  authController.login
);

/*
  Aquí agregamos la ruta para verificar la cuenta con el código enviado al correo.
*/
router.post(
  '/verify-account',
  requireJson,
  validateBody(verifyAccountSchema),
  authController.verifyAccount
);

/*
  Aquí agregamos la ruta para reenviar el código de verificación.
  Esta ruta sirve si el usuario no recibió el correo o si el código venció.
*/
router.post(
  '/resend-verification-code',
  requireJson,
  validateBody(resendVerificationCodeSchema),
  authController.resendVerificationCode
);

/*
  Aquí exportamos el router para que app.js lo pueda usar dentro de /api/auth.
*/
module.exports = router;