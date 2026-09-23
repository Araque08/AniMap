const { verifyAccessToken } = require('../utils/jwt');

function authMiddleware(req, res, next) {
  const authorization = req.get('Authorization');

  if (!authorization) {
    return res.status(401).json({
      ok: false,
      code: 'ACCESS_TOKEN_REQUIRED',
      message: 'Token de acceso requerido',
    });
  }

  const parts = authorization.trim().split(/\s+/);

  if (parts.length !== 2 || parts[0].toLowerCase() !== 'bearer' || !parts[1]) {
    return res.status(401).json({
      ok: false,
      code: 'ACCESS_TOKEN_INVALID',
      message: 'Formato de autorización inválido',
    });
  }

  try {
    const payload = verifyAccessToken(parts[1]);
    const userId = Number(payload.sub);

    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({
        ok: false,
        code: 'ACCESS_TOKEN_INVALID',
        message: 'Token de acceso inválido',
      });
    }

    req.auth = {
      userId,
      email: typeof payload.email === 'string' ? payload.email : null,
      role: typeof payload.role === 'string' ? payload.role.trim().toUpperCase() : null,
      deviceId:
        typeof payload.deviceId === 'string' && payload.deviceId.trim()
          ? payload.deviceId.trim()
          : null,
    };

    return next();
  } catch (error) {
    const message =
      error?.name === 'TokenExpiredError'
        ? 'El token de acceso ha expirado'
        : 'Token de acceso inválido';
    const code =
      error?.name === 'TokenExpiredError'
        ? 'ACCESS_TOKEN_EXPIRED'
        : 'ACCESS_TOKEN_INVALID';

    return res.status(401).json({
      ok: false,
      code,
      message,
    });
  }
}

module.exports = authMiddleware;
