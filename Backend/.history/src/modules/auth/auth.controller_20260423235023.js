const authService = require('./auth.service');

/*
  Aquí hicimos el controlador de registro.
  Su responsabilidad es recibir la petición ya validada, llamar al servicio
  y devolver una respuesta HTTP clara al frontend.
*/
async function register(req, res, next) {
  try {
    const user = await authService.registerUser(req.validatedBody);

    return res.status(201).json({
      ok: true,
      message:
        'Usuario registrado correctamente. Te enviamos un código de verificación a tu correo.',
      data: user,
    });
  } catch (error) {
    next(error);
  }
}

/*
  Aquí hicimos el controlador de login.
  Si las credenciales son correctas y la cuenta está verificada, devuelve
  los datos del usuario y los tokens.
*/
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

/*
  Aquí hicimos el controlador para verificar la cuenta.
  Recibe el correo y el código de 6 dígitos.
*/
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

/*
  Aquí hicimos el controlador para reenviar el código de verificación.
  Esto permite generar un nuevo código cuando el usuario no recibió el anterior
  o cuando el código expiró.
*/
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

/*
  Aquí exportamos todos los controladores para conectarlos con las rutas.
*/
module.exports = {
  register,
  login,
  verifyAccount,
  resendVerificationCode,
};