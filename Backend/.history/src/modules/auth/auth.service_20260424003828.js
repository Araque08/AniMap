const db = require('../../config/db');
const env = require('../../config/env');
const { hashText, compareHash } = require('../../utils/hash');
const { signAccessToken, signRefreshToken } = require('../../utils/jwt');
const { sendVerificationCodeEmail } = require('../../utils/mailer');

/*
  Aquí hicimos una función para generar códigos de verificación de 6 dígitos.
  Usamos números aleatorios y luego los convertimos a texto para poder enviarlos
  por correo y validarlos como cadena.
*/
function generateVerificationCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

/*
  Aquí hicimos una función auxiliar para crear errores HTTP controlados.
  Esto nos permite devolver mensajes claros al frontend.
*/
function createHttpError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

/*
  Aquí hicimos la función de registro.
  Creamos el usuario, su perfil, su rol y también generamos un código de verificación.
  El código se envía al correo, pero en base de datos guardamos solo su hash.
*/
async function registerUser(data) {
  const { nombre, email, telefono, password, aceptaTyC } = data;
  const client = await db.pool.connect();

  try {
    await client.query('BEGIN');

    /*
      Aquí verificamos si el correo ya existe para evitar usuarios duplicados.
    */
    const existingUser = await client.query(
      'SELECT id FROM usuario WHERE email = $1 LIMIT 1',
      [email]
    );

    if (existingUser.rowCount > 0) {
      throw createHttpError('El correo ya está registrado', 409);
    }

    /*
      Aquí encriptamos la contraseña antes de guardarla.
      No guardamos la contraseña en texto plano.
    */
    const passwordHash = await hashText(password);

    /*
      Aquí generamos el código de verificación.
      Guardamos su hash y definimos una expiración de 15 minutos.
    */
    const verificationCode = generateVerificationCode();
    const verificationCodeHash = await hashText(verificationCode);

    /*
      Aquí insertamos el usuario.
      La cuenta queda con is_verified en false hasta que confirme el código.
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

    const user = userResult.rows[0];

    /*
      Aquí creamos el perfil asociado al usuario.
    */
    await client.query(
      `
        INSERT INTO perfil (
          fk_usuario,
          foto_url,
          notificaciones_activas
        )
        VALUES ($1, NULL, TRUE)
      `,
      [user.id]
    );

    /*
      Aquí buscamos el rol USUARIO para asignárselo al nuevo usuario.
    */
    const roleResult = await client.query(
      `SELECT id FROM rol WHERE UPPER(nombre) = 'USUARIO' LIMIT 1`
    );

    if (roleResult.rowCount === 0) {
      throw createHttpError(
        'No existe el rol USUARIO. Debes crearlo antes de registrar usuarios.',
        500
      );
    }

    /*
      Aquí asociamos el usuario con el rol USUARIO.
    */
    await client.query(
      `
        INSERT INTO usuario_rol (fk_usuario, fk_rol)
        VALUES ($1, $2)
      `,
      [user.id, roleResult.rows[0].id]
    );

    await client.query('COMMIT');

    /*
      Aquí enviamos el código después de confirmar la transacción.
      Si no hay correo SMTP configurado, mailer.js imprimirá el código en consola.
    */
    await sendVerificationCodeEmail({
      to: email,
      code: verificationCode,
    });

    return user;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/*
  Aquí hicimos el inicio de sesión.
  Validamos que el usuario exista, esté activo, esté verificado y que la contraseña coincida.
*/
async function loginUser(data) {
  const { email, password, deviceId = 'mobile-app' } = data;
  const client = await db.pool.connect();

  try {
    await client.query('BEGIN');

    /*
      Aquí buscamos al usuario por correo.
    */
    const result = await client.query(
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
      [email]
    );

    if (result.rowCount === 0) {
      throw createHttpError('Credenciales inválidas', 401);
    }

    const user = result.rows[0];

    /*
      Aquí verificamos que la cuenta esté activa.
    */
    if (user.estado_cuenta !== 'ACTIVO') {
      throw createHttpError('La cuenta no está activa', 403);
    }

    /*
      Aquí bloqueamos el login si la cuenta todavía no ha sido verificada.
    */
    if (!user.is_verified) {
      throw createHttpError('La cuenta aún no ha sido verificada', 403);
    }

    /*
      Aquí comparamos la contraseña enviada con el hash guardado en la base.
    */
    const passwordOk = await compareHash(password, user.password_hash);

    if (!passwordOk) {
      throw createHttpError('Credenciales inválidas', 401);
    }

    /*
      Aquí actualizamos la fecha del último inicio de sesión.
    */
    await client.query(
      `
        UPDATE usuario
        SET last_login_at = NOW()
        WHERE id = $1
      `,
      [user.id]
    );

    /*
      Aquí generamos los tokens de sesión.
    */
    const accessToken = signAccessToken({
      sub: user.id,
      email: user.email,
      role: 'USUARIO',
    });

    const refreshToken = signRefreshToken({
      sub: user.id,
      deviceId,
    });

    const refreshTokenHash = await hashText(refreshToken);

    /*
  Aquí cerramos cualquier sesión vigente anterior del mismo usuario y dispositivo.
  Lo hacemos antes de insertar la nueva sesión para evitar conflictos con el índice único parcial.
*/
await client.query(
  `
    UPDATE device_session
    SET vigente = FALSE
    WHERE fk_usuario = $1
      AND device_id = $2
      AND vigente = TRUE
  `,
  [user.id, deviceId]
);

/*
  Aquí insertamos una nueva sesión vigente para el dispositivo.
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
      NOW() + ($4 || ' days')::interval,
      TRUE
    )
  `,
  [user.id, deviceId, refreshTokenHash, String(env.REFRESH_TOKEN_TTL_DAYS)]
);

    /*
      Aquí consultamos nuevamente al usuario para devolver datos actualizados.
    */
    const freshUserResult = await client.query(
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
      [user.id]
    );

    await client.query('COMMIT');

    return {
      user: freshUserResult.rows[0],
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
  Aquí hicimos la verificación de cuenta.
  Recibimos el correo y el código, validamos que exista, que no haya expirado
  y que coincida con el hash guardado.
*/
async function verifyAccount(data) {
  const { email, code } = data;
  const client = await db.pool.connect();

  try {
    await client.query('BEGIN');

    /*
      Aquí buscamos el usuario con sus datos de verificación.
    */
    const result = await client.query(
      `
        SELECT
          id,
          nombre,
          email,
          telefono,
          is_verified,
          estado_cuenta,
          verification_code_hash,
          verification_code_expires_at
        FROM usuario
        WHERE email = $1
        LIMIT 1
      `,
      [email]
    );

    if (result.rowCount === 0) {
      throw createHttpError('No existe una cuenta con este correo', 404);
    }

    const user = result.rows[0];

    /*
      Aquí validamos que la cuenta esté activa.
    */
    if (user.estado_cuenta !== 'ACTIVO') {
      throw createHttpError('La cuenta no está activa', 403);
    }

    /*
      Aquí evitamos verificar dos veces una cuenta que ya está verificada.
    */
    if (user.is_verified) {
      await client.query('COMMIT');

      return {
        id: user.id,
        nombre: user.nombre,
        email: user.email,
        telefono: user.telefono,
        is_verified: user.is_verified,
        estado_cuenta: user.estado_cuenta,
      };
    }

    /*
      Aquí validamos que exista un código pendiente.
    */
    if (!user.verification_code_hash || !user.verification_code_expires_at) {
      throw createHttpError('No hay un código de verificación activo', 400);
    }

    /*
      Aquí validamos que el código no haya expirado.
    */
    const expiresAt = new Date(user.verification_code_expires_at);

    if (expiresAt.getTime() < Date.now()) {
      throw createHttpError('El código de verificación ha expirado', 400);
    }

    /*
      Aquí comparamos el código escrito por el usuario contra el hash guardado.
    */
    const codeOk = await compareHash(code, user.verification_code_hash);

    if (!codeOk) {
      throw createHttpError('El código de verificación es incorrecto', 400);
    }

    /*
      Aquí marcamos la cuenta como verificada y limpiamos los datos del código.
    */
    const verifiedResult = await client.query(
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
      [user.id]
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
  Aquí hicimos el reenvío del código de verificación.
  Si el usuario existe y todavía no está verificado, generamos un nuevo código.
*/
async function resendVerificationCode(data) {
  const { email } = data;
  const client = await db.pool.connect();

  try {
    await client.query('BEGIN');

    /*
      Aquí buscamos al usuario por correo.
    */
    const result = await client.query(
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
      [email]
    );

    if (result.rowCount === 0) {
      throw createHttpError('No existe una cuenta con este correo', 404);
    }

    const user = result.rows[0];

    /*
      Aquí validamos que la cuenta esté activa.
    */
    if (user.estado_cuenta !== 'ACTIVO') {
      throw createHttpError('La cuenta no está activa', 403);
    }

    /*
      Aquí evitamos reenviar códigos a cuentas que ya están verificadas.
    */
    if (user.is_verified) {
      throw createHttpError('La cuenta ya está verificada', 400);
    }

    /*
      Aquí generamos un nuevo código y reemplazamos el anterior.
    */
    const verificationCode = generateVerificationCode();
    const verificationCodeHash = await hashText(verificationCode);

    await client.query(
      `
        UPDATE usuario
        SET
          verification_code_hash = $1,
          verification_code_expires_at = NOW() + INTERVAL '15 minutes',
          verification_code_sent_at = NOW()
        WHERE id = $2
      `,
      [verificationCodeHash, user.id]
    );

    await client.query('COMMIT');

    /*
      Aquí enviamos el nuevo código.
      Si no hay SMTP configurado, se imprime en la consola.
    */
    await sendVerificationCodeEmail({
      to: email,
      code: verificationCode,
    });

    return {
      email,
      sent: true,
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/*
  Aquí exportamos las funciones para que el controlador pueda usarlas.
*/
module.exports = {
  registerUser,
  loginUser,
  verifyAccount,
  resendVerificationCode,
};