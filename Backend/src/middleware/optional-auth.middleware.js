const { verifyAccessToken } = require('../utils/jwt');

function optionalAuthMiddleware(req, res, next) {
  const authorization = req.get('Authorization');
  if (!authorization) return next();

  const parts = authorization.trim().split(/\s+/);
  if (parts.length !== 2 || parts[0].toLowerCase() !== 'bearer' || !parts[1]) {
    return res.status(401).json({
      ok: false,
      message: 'Formato de autorización inválido',
    });
  }

  try {
    const payload = verifyAccessToken(parts[1]);
    const userId = Number(payload.sub);
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({
        ok: false,
        message: 'Token de acceso inválido',
      });
    }
    req.auth = { userId };
    return next();
  } catch (error) {
    return res.status(401).json({
      ok: false,
      message:
        error?.name === 'TokenExpiredError'
          ? 'El token de acceso ha expirado'
          : 'Token de acceso inválido',
    });
  }
}

module.exports = optionalAuthMiddleware;
