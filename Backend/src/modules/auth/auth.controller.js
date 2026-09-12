const authService = require('./auth.service');

/*
  Aquí hicimos el controlador de registro.
  Su responsabilidad es recibir la petición ya validada,
  llamar al servicio y devolver una respuesta HTTP clara
  al frontend.
*/
async function register(req, res, next) {
  try {
    const user =
      await authService.registerUser(
        req.validatedBody
      );
    const verificationEmailSent = user.verificationEmailSent;

    return res.status(201).json({
      ok: true,

      message: verificationEmailSent
        ? 'Usuario registrado correctamente. Te enviamos un código de verificación a tu correo.'
        : 'Usuario registrado correctamente, pero no fue posible enviar el correo. Solicita un nuevo código desde la pantalla de verificación.',

      data: user,
    });

  } catch (error) {
    next(error);
  }
}


/*
  Aquí hicimos el controlador de login.

  Si las credenciales son correctas y la cuenta
  está verificada, devuelve los datos del usuario
  y los tokens.
*/
async function login(req, res, next) {
  try {
    const result =
      await authService.loginUser(
        req.validatedBody
      );

    return res.status(200).json({
      ok: true,

      message:
        'Inicio de sesión exitoso',

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
    const result =
      await authService.verifyAccount(
        req.validatedBody
      );

    return res.status(200).json({
      ok: true,

      message:
        'Cuenta verificada exitosamente',

      data: result,
    });

  } catch (error) {
    next(error);
  }
}


/*
  Aquí hicimos el controlador para reenviar
  el código de verificación.

  Esto permite generar un nuevo código cuando
  el usuario no recibió el anterior o cuando
  el código expiró.
*/
async function resendVerificationCode(
  req,
  res,
  next
) {

  try {

    const result =
      await authService.resendVerificationCode(
        req.validatedBody
      );


    return res.status(200).json({

      ok: true,

      message: result.sent
        ? 'Te enviamos un nuevo código de verificación.'
        : 'El código fue renovado, pero no fue posible enviar el correo. Intenta reenviarlo nuevamente.',

      data: result,

    });


  } catch (error) {

    next(error);

  }

}


/*
  ============================================================
  RECUPERACIÓN DE CONTRASEÑA
  ============================================================
*/


/*
  Aquí hicimos el controlador para solicitar
  la recuperación de contraseña.

  Recibe el correo del usuario y llama al servicio,
  que se encarga de generar y enviar el código temporal.
*/
async function forgotPassword(
  req,
  res,
  next
) {

  try {

    const result =
      await authService.requestPasswordReset(
        req.validatedBody
      );


    return res.status(200).json({

      ok: true,

      message: result.sent
        ? 'Te enviamos un código para recuperar tu contraseña.'
        : 'El código fue generado, pero no fue posible enviar el correo.',

      data: result,

    });


  } catch (error) {

    next(error);

  }

}


/*
  Aquí hicimos el controlador que permite
  restablecer la contraseña.

  Recibe:

  - correo
  - código de recuperación
  - nueva contraseña
  - confirmación de contraseña

  La validación de las contraseñas se realiza
  previamente mediante Zod.

  El servicio se encarga de validar el código,
  verificar su expiración y reemplazar la contraseña.
*/
async function resetPassword(
  req,
  res,
  next
) {

  try {

    const result =
      await authService.resetPassword(
        req.validatedBody
      );


    return res.status(200).json({

      ok: true,

      message:
        'Contraseña restablecida correctamente.',

      data: result,

    });


  } catch (error) {

    next(error);

  }

}


/*
  Aquí exportamos todos los controladores
  para conectarlos con las rutas.
*/
module.exports = {

  register,

  login,

  verifyAccount,

  resendVerificationCode,

  forgotPassword,

  resetPassword,

};
