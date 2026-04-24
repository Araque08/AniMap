const db = require('../../config/db');
const env = require('../../config/env');
const { hashText, compareHash } = require('../../utils/hash');
const { signAccessToken, signRefreshToken } = require('../../utils/jwt');

async function registerUser(data) {
  const { nombre, email, telefono, password, aceptaTyC } = data;
  const client = await db.pool.connect();

  try {
    await client.query('BEGIN');

    const existingUser = await client.query(
      'SELECT id FROM usuario WHERE email = $1 LIMIT 1',
      [email]
    );

    if (existingUser.rowCount > 0) {
      const error = new Error('El correo ya está registrado');
      error.statusCode = 409;
      throw error;
    }

    const passwordHash = await hashText(password);

    const userResult = await client.query(
      `
        INSERT INTO usuario (
          nombre,
          email,
          telefono,
          password_hash,
          acepta_tyc
        )
        VALUES ($1, $2, $3, $4, $5)
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
      [nombre, email, telefono, passwordHash, aceptaTyC]
    );

    const user = userResult.rows[0];

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

    const roleResult = await client.query(
      `SELECT id FROM rol WHERE UPPER(nombre) = 'USUARIO' LIMIT 1`
    );

    if (roleResult.rowCount === 0) {
      const error = new Error(
        'No existe el rol USUARIO. Debes crearlo antes de registrar usuarios.'
      );
      error.statusCode = 500;
      throw error;
    }

    await client.query(
      `
        INSERT INTO usuario_rol (fk_usuario, fk_rol)
        VALUES ($1, $2)
      `,
      [user.id, roleResult.rows[0].id]
    );

    await client.query('COMMIT');

    return user;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function loginUser(data) {
  const { email, password, deviceId = 'mobile-app' } = data;
  const client = await db.pool.connect();

  try {
    await client.query('BEGIN');

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
      const error = new Error('Credenciales inválidas');
      error.statusCode = 401;
      throw error;
    }

    const user = result.rows[0];

    if (user.estado_cuenta !== 'ACTIVO') {
      const error = new Error('La cuenta no está activa');
      error.statusCode = 403;
      throw error;
    }

    if (!user.is_verified) {
      const error = new Error('La cuenta aún no ha sido verificada');
      error.statusCode = 403;
      throw error;
    }

    const passwordOk = await compareHash(password, user.password_hash);

    if (!passwordOk) {
      const error = new Error('Credenciales inválidas');
      error.statusCode = 401;
      throw error;
    }

    await client.query(
      `
        UPDATE usuario
        SET last_login_at = NOW()
        WHERE id = $1
      `,
      [user.id]
    );

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
        ON CONFLICT (fk_usuario, device_id)
        DO UPDATE SET
          refresh_token_hash = EXCLUDED.refresh_token_hash,
          creado_en = NOW(),
          expira_en = EXCLUDED.expira_en,
          vigente = TRUE
      `,
      [user.id, deviceId, refreshTokenHash, String(env.REFRESH_TOKEN_TTL_DAYS)]
    );

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

module.exports = {
  registerUser,
  loginUser,
};