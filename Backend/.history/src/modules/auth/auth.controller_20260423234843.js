const authService = require('./auth.service');

async function register(req, res, next) {
  try {
    const user = await authService.registerUser(req.validatedBody);

    return res.status(201).json({
      ok: true,
      message: 'Usuario registrado correctamente. Te enviamos un código de verificación a tu correo.',
      data: user,
    });
  } catch (error) {
    next(error);
  }
}

async function login(req, res, next) {
  try {
    const result = await authService.loginUser(req.validatedBody);

    return res.status(200).json({
      ok: true,
      message: 'Inicio de sesión exitoso',
      data: result,
    });
  } catch (error) {
    next(error);
  }
}

async function verifyAccount(req, res, next) {
  try {
    const result = await authService.verifyAccount(req.validatedBody);

    return res.status(200).json({
      ok: true,
      message: 'Cuenta verificada exitosamente',
      data: result,
    });
  } catch (error) {
    next(error);
  }
}

async function resendVerificationCode(req, res, next) {
  try {
    const result = await authService.resendVerificationCode(req.validatedBody);

    return res.status(200).json({
      ok: true,
      message: 'Te enviamos un nuevo código de verificación.',
      data: result,
    });
  } catch (error) {
    next(error);
  }
}

module.exports = {
  register,
  login,
  verifyAccount,
  resendVerificationCode,
};