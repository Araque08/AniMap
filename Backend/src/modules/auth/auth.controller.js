const authService = require('./auth.service');

async function register(req, res, next) {
  try {
    const user = await authService.registerUser(req.validatedBody);

    return res.status(201).json({
      ok: true,
      message: 'Usuario registrado correctamente',
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

module.exports = {
  register,
  login,
};