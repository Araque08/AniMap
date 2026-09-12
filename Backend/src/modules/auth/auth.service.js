const db = require('../../config/postgres_db');
const env = require('../../config/env');

const { hashText, compareHash } = require('../../utils/hash');

const { randomInt } = require('node:crypto');

const {
  signAccessToken,
  signRefreshToken,
} = require('../../utils/jwt');

const {
  sendVerificationCodeEmail,
  sendPasswordResetCodeEmail,
} = require('../../utils/mailer');


/*
  ============================================================
  FUNCIONES AUXILIARES
  ============================================================
*/


/*
  Aquí generamos un código de verificación de cuenta
  compuesto por 6 dígitos.
*/
function generateVerificationCode() {
  return String(randomInt(100000, 1000000));
}


/*
  Aquí generamos un código de recuperación de contraseña
  de 6 dígitos.

  Para recuperación utilizamos randomInt de crypto.
*/
function generatePasswordResetCode() {
  return String(
    randomInt(100000, 1000000)
  );
}


/*
  Aquí creamos errores HTTP controlados para poder enviar
  códigos de estado y mensajes claros al frontend.
*/
function createHttpError(message, statusCode) {
  const error = new Error(message);

  error.statusCode = statusCode;

  return error;
}


/*
  ============================================================
  REGISTRO DE USUARIO
  ============================================================
*/

async function registerUser(data) {

  const {
    nombre,
    email,
    telefono,
    password,
    aceptaTyC,
  } = data;

  const client = await db.pool.connect();
  let transactionOpen = false;

  try {

    await client.query('BEGIN');
    transactionOpen = true;


    /*
      Verificamos si ya existe un usuario con ese correo.
    */
    const existingUser = await client.query(
      `
        SELECT id
        FROM usuario
        WHERE email = $1
        LIMIT 1
      `,
      [email]
    );


    if (existingUser.rowCount > 0) {

      throw createHttpError(
        'El correo ya está registrado',
        409
      );

    }


    /*
      Encriptamos la contraseña antes de almacenarla.
    */
    const passwordHash =
      await hashText(password);


    /*
      Generamos código de verificación.
    */
    const verificationCode =
      generateVerificationCode();


    /*
      Guardamos solamente el hash del código.
    */
    const verificationCodeHash =
      await hashText(
        verificationCode
      );


    /*
      Creamos el usuario.
    */
    const userResult = await client.query(
      `
        INSERT INTO usuario (

          nombre,
          email,
          telefono,
          password_hash,
          acepta_tyc,

          verification_code_hash,
          verification_code_expires_at,
          verification_code_sent_at

        )

        VALUES (

          $1,
          $2,
          $3,
          $4,
          $5,
          $6,

          NOW() + INTERVAL '15 minutes',
          NOW()

        )

        RETURNING

          id,
          nombre,
          email,
          telefono,
          is_verified,
          estado_cuenta,
          fecha_registro,
          last_login_at
      `,
      [
        nombre,
        email,
        telefono,
        passwordHash,
        aceptaTyC,
        verificationCodeHash,
      ]
    );


    const user =
      userResult.rows[0];


    /*
      Creamos el perfil asociado al usuario.
    */
    await client.query(
      `
        INSERT INTO perfil (

          fk_usuario,
          foto_url,
          notificaciones_activas

        )

        VALUES (

          $1,
          NULL,
          TRUE

        )
      `,
      [
        user.id
      ]
    );


    /*
      Buscamos el rol USUARIO.
    */
    const roleResult =
      await client.query(
        `
          SELECT id

          FROM rol

          WHERE UPPER(nombre) = 'USUARIO'

          LIMIT 1
        `
      );


    if (roleResult.rowCount === 0) {

      throw createHttpError(
        'No existe el rol USUARIO. Debes crearlo antes de registrar usuarios.',
        500
      );

    }


    /*
      Asociamos el usuario con su rol.
    */
    await client.query(
      `
        INSERT INTO usuario_rol (

          fk_usuario,
          fk_rol

        )

        VALUES (

          $1,
          $2

        )
      `,
      [
        user.id,
        roleResult.rows[0].id,
      ]
    );


    await client.query('COMMIT');
    transactionOpen = false;


    let verificationEmailSent = true;

    try {
      await sendVerificationCodeEmail({
        to: email,
        code: verificationCode,
      });
    } catch (_) {
      verificationEmailSent = false;
    }

    return {
      ...user,
      verificationEmailSent,
    };


  } catch (error) {

    if (transactionOpen) {
      await client.query('ROLLBACK');
    }

    if (error.code === '23505') {
      throw createHttpError('El correo ya está registrado', 409);
    }

    throw error;


  } finally {

    client.release();

  }

}


/*
  ============================================================
  INICIO DE SESIÓN
  ============================================================
*/

async function loginUser(data) {

  const {

    email,
    password,

    deviceId = 'mobile-app',

  } = data;


  const client =
    await db.pool.connect();


  try {

    await client.query('BEGIN');


    /*
      Buscamos el usuario.
    */
    const result =
      await client.query(
        `
          SELECT

            id,
            nombre,
            email,
            telefono,
            password_hash,
            is_verified,
            estado_cuenta,
            last_login_at

          FROM usuario

          WHERE email = $1

          LIMIT 1
        `,
        [
          email
        ]
      );


    if (result.rowCount === 0) {

      throw createHttpError(
        'Credenciales inválidas',
        401
      );

    }


    const user =
      result.rows[0];


    /*
      Verificamos que la cuenta esté activa.
    */
    if (
      user.estado_cuenta !== 'ACTIVO'
    ) {

      throw createHttpError(
        'La cuenta no está activa',
        403
      );

    }


    /*
      Verificamos que la cuenta esté verificada.
    */
    if (!user.is_verified) {

      throw createHttpError(
        'La cuenta aún no ha sido verificada',
        403
      );

    }


    /*
      Comparamos la contraseña.
    */
    const passwordOk =
      await compareHash(
        password,
        user.password_hash
      );


    if (!passwordOk) {

      throw createHttpError(
        'Credenciales inválidas',
        401
      );

    }


    /*
      Actualizamos último inicio de sesión.
    */
    await client.query(
      `
        UPDATE usuario

        SET
          last_login_at = NOW()

        WHERE id = $1
      `,
      [
        user.id
      ]
    );


    /*
      Creamos Access Token.
    */
    const accessToken =
      signAccessToken({

        sub: user.id,

        email: user.email,

        role: 'USUARIO',

      });


    /*
      Creamos Refresh Token.
    */
    const refreshToken =
      signRefreshToken({

        sub: user.id,

        deviceId,

      });


    const refreshTokenHash =
      await hashText(
        refreshToken
      );


    /*
      Cerramos sesiones anteriores del mismo dispositivo.
    */
    await client.query(
      `
        UPDATE device_session

        SET
          vigente = FALSE

        WHERE
          fk_usuario = $1

          AND device_id = $2

          AND vigente = TRUE
      `,
      [
        user.id,
        deviceId,
      ]
    );


    /*
      Registramos la nueva sesión.
    */
    await client.query(
      `
        INSERT INTO device_session (

          fk_usuario,
          device_id,
          refresh_token_hash,
          creado_en,
          expira_en,
          vigente

        )

        VALUES (

          $1,
          $2,
          $3,

          NOW(),

          NOW()
          + ($4 || ' days')::interval,

          TRUE

        )
      `,
      [

        user.id,

        deviceId,

        refreshTokenHash,

        String(
          env.REFRESH_TOKEN_TTL_DAYS
        ),

      ]
    );


    /*
      Consultamos nuevamente los datos actualizados.
    */
    const freshUserResult =
      await client.query(
        `
          SELECT

            id,
            nombre,
            email,
            telefono,
            is_verified,
            estado_cuenta,
            fecha_registro,
            last_login_at

          FROM usuario

          WHERE id = $1
        `,
        [
          user.id
        ]
      );


    await client.query('COMMIT');


    return {

      user:
        freshUserResult.rows[0],

      accessToken,

      refreshToken,

    };


  } catch (error) {

    await client.query('ROLLBACK');

    throw error;


  } finally {

    client.release();

  }

}


/*
  ============================================================
  VERIFICACIÓN DE CUENTA
  ============================================================
*/

async function verifyAccount(data) {

  const {
    email,
    code,
  } = data;


  const client =
    await db.pool.connect();


  try {

    await client.query('BEGIN');


    /*
      Buscamos el usuario.
    */
    const result =
      await client.query(
        `
          SELECT

            id,
            nombre,
            email,
            telefono,
            is_verified,
            estado_cuenta,
            verification_code_hash,
            verification_code_expires_at,
            verification_code_expires_at <= NOW() AS verification_code_expired

          FROM usuario

          WHERE email = $1

          LIMIT 1
        `,
        [
          email
        ]
      );


    if (result.rowCount === 0) {

      throw createHttpError(
        'No existe una cuenta con este correo',
        404
      );

    }


    const user =
      result.rows[0];


    if (
      user.estado_cuenta !== 'ACTIVO'
    ) {

      throw createHttpError(
        'La cuenta no está activa',
        403
      );

    }


    /*
      Una cuenta ya verificada no debe reutilizar el flujo del código.
    */
    if (user.is_verified) {
      throw createHttpError('La cuenta ya está verificada', 400);
    }


    /*
      Validamos que exista código.
    */
    if (
      !user.verification_code_hash
      ||
      !user.verification_code_expires_at
    ) {

      throw createHttpError(
        'No hay un código de verificación activo',
        400
      );

    }


    /*
      PostgreSQL evalúa la expiración para evitar diferencias de zona horaria.
    */
    if (user.verification_code_expired) {
      throw createHttpError('El código de verificación ha expirado', 400);
    }


    /*
      Comparamos el código con su hash.
    */
    const codeOk =
      await compareHash(

        code,

        user.verification_code_hash

      );


    if (!codeOk) {

      throw createHttpError(
        'El código de verificación es incorrecto',
        400
      );

    }


    /*
      Verificamos la cuenta y eliminamos el código usado.
    */
    const verifiedResult =
      await client.query(
        `
          UPDATE usuario

          SET

            is_verified = TRUE,

            verification_code_hash = NULL,

            verification_code_expires_at = NULL,

            verification_code_sent_at = NULL

          WHERE id = $1

          RETURNING

            id,
            nombre,
            email,
            telefono,
            is_verified,
            estado_cuenta,
            fecha_registro,
            last_login_at
        `,
        [
          user.id
        ]
      );


    await client.query('COMMIT');


    return verifiedResult.rows[0];


  } catch (error) {

    await client.query('ROLLBACK');

    throw error;


  } finally {

    client.release();

  }

}


/*
  ============================================================
  REENVIAR CÓDIGO DE VERIFICACIÓN
  ============================================================
*/

async function resendVerificationCode(data) {

  const {
    email
  } = data;


  const client =
    await db.pool.connect();
  let transactionOpen = false;


  try {

    await client.query('BEGIN');
    transactionOpen = true;


    const result =
      await client.query(
        `
          SELECT

            id,
            nombre,
            email,
            telefono,
            is_verified,
            estado_cuenta

          FROM usuario

          WHERE email = $1

          LIMIT 1
        `,
        [
          email
        ]
      );


    if (result.rowCount === 0) {

      throw createHttpError(
        'No existe una cuenta con este correo',
        404
      );

    }


    const user =
      result.rows[0];


    if (
      user.estado_cuenta !== 'ACTIVO'
    ) {

      throw createHttpError(
        'La cuenta no está activa',
        403
      );

    }


    if (user.is_verified) {

      throw createHttpError(
        'La cuenta ya está verificada',
        400
      );

    }


    const verificationCode =
      generateVerificationCode();


    const verificationCodeHash =
      await hashText(
        verificationCode
      );


    await client.query(
      `
        UPDATE usuario

        SET

          verification_code_hash = $1,

          verification_code_expires_at =
            NOW() + INTERVAL '15 minutes',

          verification_code_sent_at =
            NOW()

        WHERE id = $2
      `,
      [
        verificationCodeHash,
        user.id,
      ]
    );


    await client.query('COMMIT');
    transactionOpen = false;


    let sent = true;

    try {
      await sendVerificationCodeEmail({
        to: email,
        code: verificationCode,
      });
    } catch (_) {
      sent = false;
    }


    return {

      email,

      sent,

    };


  } catch (error) {

    if (transactionOpen) {
      await client.query('ROLLBACK');
    }

    throw error;


  } finally {

    client.release();

  }

}


/*
  ============================================================
  SOLICITAR RECUPERACIÓN DE CONTRASEÑA
  ============================================================

  Este método corresponde a:

  POST /forgot-password

  Recibe:

  {
    "email": "correo@gmail.com"
  }

  Genera un código temporal y envía el código al correo.
*/

async function requestPasswordReset(data) {

  const {
    email
  } = data;


  const client =
    await db.pool.connect();
  let transactionOpen = false;


  try {

    await client.query('BEGIN');
    transactionOpen = true;


    /*
      Buscamos la cuenta.
    */
    const result =
      await client.query(
        `
          SELECT

            id,
            email,
            estado_cuenta

          FROM usuario

          WHERE email = $1

          LIMIT 1
        `,
        [
          email
        ]
      );


    /*
      El correo debe existir.
    */
    if (result.rowCount === 0) {

      throw createHttpError(
        'No existe una cuenta con este correo',
        404
      );

    }


    const user =
      result.rows[0];


    /*
      La cuenta debe estar activa.
    */
    if (
      user.estado_cuenta !== 'ACTIVO'
    ) {

      throw createHttpError(
        'La cuenta no está activa',
        403
      );

    }


    /*
      Generamos el código temporal.
    */
    const resetCode =
      generatePasswordResetCode();


    /*
      Guardamos únicamente su hash.
    */
    const resetCodeHash =
      await hashText(
        resetCode
      );


    /*
      Guardamos el código de recuperación.

      Tendrá una vigencia de 15 minutos.
    */
    await client.query(
      `
        UPDATE usuario

        SET

          password_reset_code_hash = $1,

          password_reset_code_expires_at =
            NOW() + INTERVAL '15 minutes',

          password_reset_code_sent_at =
            NOW()

        WHERE id = $2
      `,
      [
        resetCodeHash,
        user.id,
      ]
    );


    await client.query('COMMIT');
    transactionOpen = false;


    let sent = true;

    try {
      await sendPasswordResetCodeEmail({
        to: user.email,
        code: resetCode,
      });
    } catch (_) {
      sent = false;
    }


    return {

      email:
        user.email,

      sent,

    };


  } catch (error) {

    if (transactionOpen) {
      await client.query('ROLLBACK');
    }


    throw error;


  } finally {

    client.release();

  }

}


/*
  ============================================================
  RESTABLECER CONTRASEÑA
  ============================================================

  Este método corresponde a:

  POST /reset-password

  Recibe:

  {
    "email": "correo@gmail.com",
    "code": "123456",
    "newPassword": "Nueva123*",
    "confirmPassword": "Nueva123*"
  }

  confirmPassword ya fue validado previamente por Zod.
*/

async function resetPassword(data) {

  const {

    email,

    code,

    newPassword,

  } = data;


  const client =
    await db.pool.connect();


  try {

    await client.query('BEGIN');


    /*
      Buscamos los datos de recuperación del usuario.

      FOR UPDATE bloquea temporalmente el registro
      mientras se realiza el cambio.
    */
    const result =
      await client.query(
        `
          SELECT

            id,
            email,
            estado_cuenta,
            password_reset_code_hash,
            password_reset_code_expires_at,
            password_reset_code_expires_at <= NOW() AS password_reset_code_expired

          FROM usuario

          WHERE email = $1

          LIMIT 1

          FOR UPDATE
        `,
        [
          email
        ]
      );


    /*
      Validamos existencia del correo.
    */
    if (result.rowCount === 0) {

      throw createHttpError(
        'No existe una cuenta con este correo',
        404
      );

    }


    const user =
      result.rows[0];


    /*
      Validamos estado de la cuenta.
    */
    if (
      user.estado_cuenta !== 'ACTIVO'
    ) {

      throw createHttpError(
        'La cuenta no está activa',
        403
      );

    }


    /*
      Debe existir un código de recuperación pendiente.
    */
    if (

      !user.password_reset_code_hash

      ||

      !user.password_reset_code_expires_at

    ) {

      throw createHttpError(
        'No hay un código de recuperación activo',
        400
      );

    }


    /*
      PostgreSQL evalúa la expiración para evitar diferencias de zona horaria.
    */
    if (user.password_reset_code_expired) {
      throw createHttpError('El código de recuperación ha expirado', 400);
    }


    /*
      Comparamos el código recibido con el hash.
    */
    const codeOk =
      await compareHash(

        code,

        user.password_reset_code_hash

      );


    if (!codeOk) {

      throw createHttpError(
        'El código de recuperación es incorrecto',
        400
      );

    }


    /*
      Generamos el hash de la nueva contraseña.
    */
    const newPasswordHash =
      await hashText(
        newPassword
      );


    /*
      Reemplazamos la contraseña anterior.

      También eliminamos completamente el código
      de recuperación para impedir que vuelva a usarse.
    */
    await client.query(
      `
        UPDATE usuario

        SET

          password_hash = $1,

          password_reset_code_hash = NULL,

          password_reset_code_expires_at = NULL,

          password_reset_code_sent_at = NULL

        WHERE id = $2
      `,
      [
        newPasswordHash,
        user.id,
      ]
    );


    /*
      Cerramos cualquier sesión que estuviera vigente.

      De esta manera las sesiones antiguas tendrán
      que volver a autenticarse.
    */
    await client.query(
      `
        UPDATE device_session

        SET
          vigente = FALSE

        WHERE
          fk_usuario = $1

          AND vigente = TRUE
      `,
      [
        user.id
      ]
    );


    await client.query('COMMIT');


    return {

      email:
        user.email,

      passwordReset:
        true,

    };


  } catch (error) {

    await client.query('ROLLBACK');

    throw error;


  } finally {

    client.release();

  }

}


/*
  ============================================================
  EXPORTACIONES
  ============================================================
*/

module.exports = {

  registerUser,

  loginUser,

  verifyAccount,

  resendVerificationCode,

  requestPasswordReset,

  resetPassword,

};
