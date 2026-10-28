const db = require('../config/postgres_db');
const env = require('../config/env');
const { verifyAccessToken } = require('../utils/jwt');
const { getSingleRole } = require('../modules/auth/auth.role.service');

async function authMiddleware(req, res, next) {
  const authorization = req.get('Authorization');

  if (!authorization) {
    return res.status(401).json({
      ok: false,
      code: 'ACCESS_TOKEN_REQUIRED',
      message: 'Token de acceso requerido',
    });
  }

  const parts = authorization.trim().split(/\s+/);

  if (
    parts.length !== 2 ||
    parts[0].toLowerCase() !== 'bearer' ||
    !parts[1]
  ) {
    return res.status(401).json({
      ok: false,
      code: 'ACCESS_TOKEN_INVALID',
      message: 'Formato de autorización inválido',
    });
  }

  let payload;

  try {
    payload = verifyAccessToken(parts[1]);
  } catch (error) {
    const expired = error?.name === 'TokenExpiredError';

    return res.status(401).json({
      ok: false,
      code: expired
        ? 'ACCESS_TOKEN_EXPIRED'
        : 'ACCESS_TOKEN_INVALID',
      message: expired
        ? 'El token de acceso ha expirado'
        : 'Token de acceso inválido',
    });
  }

  const userId = Number(payload.sub);
  const deviceId =
    typeof payload.deviceId === 'string'
      ? payload.deviceId.trim()
      : '';

  if (!Number.isInteger(userId) || userId <= 0 || !deviceId) {
    return res.status(401).json({
      ok: false,
      code: 'ACCESS_TOKEN_INVALID',
      message: 'Token de acceso inválido',
    });
  }

  try {
    /*
      Validamos la sesión directamente contra PostgreSQL.

      De esta forma un access token deja de ser suficiente
      si la sesión fue revocada desde otro dispositivo.
    */
    const result = await db.query(
      `
        SELECT
          ds.id AS session_id,
          ds.expira_en,
          (ds.expira_en <= LOCALTIMESTAMP) AS session_expired,
          u.email,
          u.is_verified,
          u.estado_cuenta

        FROM device_session ds

        INNER JOIN usuario u
          ON u.id = ds.fk_usuario

        WHERE
          ds.fk_usuario = $1
          AND ds.device_id = $2
          AND ds.vigente = TRUE

        ORDER BY ds.id DESC

        LIMIT 1
      `,
      [userId, deviceId]
    );

    if (result.rowCount === 0) {
      return res.status(401).json({
        ok: false,
        code: 'SESSION_REVOKED',
        message: 'La sesión no está activa',
      });
    }

    const session = result.rows[0];

    /*
      Si superó el tiempo permitido de inactividad,
      invalidamos la sesión.
    */
    if (session.session_expired) {
      await db.query(
        `
          UPDATE device_session
          SET vigente = FALSE
          WHERE id = $1
        `,
        [session.session_id]
      );

      return res.status(401).json({
        ok: false,
        code: 'SESSION_EXPIRED',
        message: 'La sesión expiró por inactividad',
      });
    }

    /*
      También verificamos el estado actual de la cuenta.
    */
    if (
      session.estado_cuenta !== 'ACTIVO' ||
      !session.is_verified
    ) {
      await db.query(
        `
          UPDATE device_session
          SET vigente = FALSE
          WHERE id = $1
        `,
        [session.session_id]
      );

      return res.status(403).json({
        ok: false,
        code: 'ACCOUNT_INVALID',
        message: 'La cuenta no está disponible',
      });
    }

    /*
      Consultamos el rol vigente directamente en PostgreSQL.

      No usamos el rol almacenado dentro del JWT para
      autorizar rutas administrativas.
    */
    const role = await getSingleRole(db, userId);

    const idleMinutes =
      Number.isFinite(env.SESSION_IDLE_TIMEOUT_MINUTES) &&
      env.SESSION_IDLE_TIMEOUT_MINUTES > 0
        ? env.SESSION_IDLE_TIMEOUT_MINUTES
        : 30;

    /*
      Renovamos la expiración de la sesión porque el usuario
      acaba de realizar actividad válida.
    */
    const renewed = await db.query(
      `
        UPDATE device_session
        SET expira_en =
          NOW() + ($2::int * INTERVAL '1 minute')
        WHERE
          id = $1
          AND vigente = TRUE
          AND expira_en > LOCALTIMESTAMP
      `,
      [session.session_id, idleMinutes]
    );
    if (renewed.rowCount !== 1) {
      return res.status(401).json({
        ok: false,
        code: 'SESSION_REVOKED',
        message: 'La sesión no está activa',
      });
    }

    req.auth = {
      userId,
      email: session.email,
      role,
      deviceId,
      sessionId: session.session_id,
    };

    return next();
  } catch (error) {
    if (error?.statusCode) {
      return res.status(error.statusCode).json({
        ok: false,
        code: error.code || 'AUTHORIZATION_ERROR',
        message: error.message,
      });
    }

    console.error(
      'Error en middleware de autenticación:',
      error
    );

    return res.status(500).json({
      ok: false,
      code: 'AUTHENTICATION_ERROR',
      message: 'Error al validar la sesión',
    });
  }
}

module.exports = authMiddleware;
