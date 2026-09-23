const { randomUUID } = require('node:crypto');
const db = require('../../config/postgres_db');
const env = require('../../config/env');
const { getSingleRole } = require('./auth.role.service');
const {
  compareRefreshToken,
  hashRefreshToken,
} = require('../../utils/hash');
const {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} = require('../../utils/jwt');

function createHttpError(message, statusCode, code) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.code = code;
  return error;
}

function decodeRefreshToken(refreshToken, { allowExpired = false } = {}) {
  try {
    const payload = verifyRefreshToken(refreshToken, {
      ignoreExpiration: allowExpired,
    });
    const userId = Number(payload.sub);
    const deviceId = payload.deviceId?.toString();
    if (!Number.isInteger(userId) || userId <= 0 || !deviceId) {
      throw createHttpError('Refresh token inválido', 401, 'REFRESH_TOKEN_INVALID');
    }
    return { userId, deviceId };
  } catch (error) {
    if (error.statusCode) throw error;
    if (error.name === 'TokenExpiredError') {
      throw createHttpError('El refresh token ha expirado', 401, 'REFRESH_TOKEN_EXPIRED');
    }
    throw createHttpError('Refresh token inválido', 401, 'REFRESH_TOKEN_INVALID');
  }
}

function createAuthSessionService({
  pool = db.pool,
  compareToken = compareRefreshToken,
  hashToken = hashRefreshToken,
  accessSigner = signAccessToken,
  refreshSigner = signRefreshToken,
} = {}) {
  async function lockSession(client, userId, deviceId) {
    return client.query(
      `SELECT
         ds.id, ds.fk_usuario, ds.device_id, ds.refresh_token_hash,
         ds.vigente, ds.expira_en <= NOW() AS session_expired,
         u.email, u.is_verified, u.estado_cuenta
       FROM device_session ds
       INNER JOIN usuario u ON u.id = ds.fk_usuario
       WHERE ds.fk_usuario = $1 AND ds.device_id = $2
       ORDER BY ds.id DESC
       LIMIT 1
       FOR UPDATE OF ds`,
      [userId, deviceId]
    );
  }

  async function refreshSession(refreshToken) {
    const { userId, deviceId } = decodeRefreshToken(refreshToken);
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const result = await lockSession(client, userId, deviceId);
      if (result.rowCount === 0) {
        throw createHttpError('Sesión no encontrada', 401, 'REFRESH_TOKEN_INVALID');
      }
      const session = result.rows[0];
      const tokenMatches = await compareToken(refreshToken, session.refresh_token_hash);
      if (!tokenMatches) {
        throw createHttpError('Refresh token inválido', 401, 'REFRESH_TOKEN_INVALID');
      }
      if (!session.vigente) {
        throw createHttpError('La sesión fue revocada', 401, 'SESSION_REVOKED');
      }
      if (session.session_expired) {
        await client.query('UPDATE device_session SET vigente = FALSE WHERE id = $1', [session.id]);
        throw createHttpError('La sesión ha expirado', 401, 'REFRESH_TOKEN_EXPIRED');
      }
      if (session.estado_cuenta !== 'ACTIVO' || !session.is_verified) {
        await client.query('UPDATE device_session SET vigente = FALSE WHERE id = $1', [session.id]);
        throw createHttpError('La cuenta no está disponible', 403, 'ACCOUNT_INVALID');
      }

      const role = await getSingleRole(client, session.fk_usuario);
      const accessToken = accessSigner({
        sub: session.fk_usuario,
        email: session.email,
        role,
        deviceId: session.device_id,
      });
      const nextRefreshToken = refreshSigner({
        sub: session.fk_usuario,
        deviceId: session.device_id,
        jti: randomUUID(),
      });
      const nextHash = await hashToken(nextRefreshToken);
      await client.query(
        `UPDATE device_session
         SET refresh_token_hash = $1,
             expira_en = NOW() + ($2 || ' days')::interval,
             vigente = TRUE
         WHERE id = $3`,
        [nextHash, String(env.REFRESH_TOKEN_TTL_DAYS), session.id]
      );
      await client.query('COMMIT');
      return { accessToken, refreshToken: nextRefreshToken, role };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async function logoutSession(refreshToken) {
    const { userId, deviceId } = decodeRefreshToken(refreshToken, {
      allowExpired: true,
    });
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const result = await lockSession(client, userId, deviceId);
      if (result.rowCount === 0) {
        throw createHttpError('Sesión no encontrada', 401, 'REFRESH_TOKEN_INVALID');
      }
      const session = result.rows[0];
      const tokenMatches = await compareToken(refreshToken, session.refresh_token_hash);
      if (!tokenMatches) {
        throw createHttpError('Refresh token inválido', 401, 'REFRESH_TOKEN_INVALID');
      }
      if (!session.vigente) {
        throw createHttpError('La sesión ya fue revocada', 401, 'SESSION_REVOKED');
      }
      await client.query('UPDATE device_session SET vigente = FALSE WHERE id = $1', [session.id]);
      await client.query('COMMIT');
      return { revoked: true };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  function safeDeviceId(deviceId) {
    const value = deviceId?.toString() ?? '';
    const suffix = value.slice(-6);
    return suffix ? `••••${suffix}` : 'Dispositivo';
  }

  async function listSessions(userId, currentDeviceId) {
    const result = await pool.query(
      `SELECT id, device_id, creado_en, expira_en
       FROM device_session
       WHERE fk_usuario = $1
         AND vigente = TRUE
         AND expira_en > NOW()
       ORDER BY
         CASE WHEN device_id = $2 THEN 0 ELSE 1 END,
         creado_en DESC,
         id DESC`,
      [userId, currentDeviceId]
    );
    return result.rows.map((session) => ({
      id: session.id,
      deviceId: safeDeviceId(session.device_id),
      creadoEn: session.creado_en,
      expiraEn: session.expira_en,
      isCurrent:
        Boolean(currentDeviceId) && session.device_id === currentDeviceId,
    }));
  }

  async function revokeSession(userId, currentDeviceId, sessionId) {
    const normalizedId = Number(sessionId);
    if (!Number.isInteger(normalizedId) || normalizedId <= 0) {
      throw createHttpError('Sesión no encontrada', 404, 'SESSION_NOT_FOUND');
    }

    const result = await pool.query(
      `UPDATE device_session
       SET vigente = FALSE
       WHERE id = $1
         AND fk_usuario = $2
         AND vigente = TRUE
         AND expira_en > NOW()
         AND device_id <> $3
       RETURNING id`,
      [normalizedId, userId, currentDeviceId]
    );
    if (result.rowCount === 1) return { revoked: true };

    const current = await pool.query(
      `SELECT 1
       FROM device_session
       WHERE id = $1 AND fk_usuario = $2 AND device_id = $3
       LIMIT 1`,
      [normalizedId, userId, currentDeviceId]
    );
    if (current.rowCount === 1) {
      throw createHttpError(
        'Usa Cerrar sesión para finalizar la sesión actual',
        409,
        'CURRENT_SESSION'
      );
    }
    throw createHttpError('Sesión no encontrada', 404, 'SESSION_NOT_FOUND');
  }

  return { listSessions, logoutSession, refreshSession, revokeSession };
}

module.exports = {
  createAuthSessionService,
  authSessionService: createAuthSessionService(),
  decodeRefreshToken,
};
