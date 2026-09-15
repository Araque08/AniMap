const { verifyAccessToken } = require('../utils/jwt');

/*
  Middleware de autenticación de AniMap.

  Verifica que la petición contenga un Access Token válido
  en el encabezado Authorization.

  Formato esperado:

  Authorization: Bearer TOKEN
*/
function authMiddleware(req, res, next) {
  const authorization = req.get('Authorization');

  /*
    Si no existe el encabezado Authorization,
    el usuario no está autenticado.
  */
  if (!authorization) {
    return res.status(401).json({
      ok: false,
      message: 'Token de acceso requerido',
    });
  }

  /*
    Separamos:

    Bearer TOKEN

    en:

    ['Bearer', 'TOKEN']
  */
  const parts = authorization.trim().split(/\s+/);

  if (
    parts.length !== 2 ||
    parts[0].toLowerCase() !== 'bearer' ||
    !parts[1]
  ) {
    return res.status(401).json({
      ok: false,
      message: 'Formato de autorización inválido',
    });
  }

  try {
    /*
      Verificamos la firma y expiración del JWT.
    */
    const payload = verifyAccessToken(parts[1]);

    const userId = Number(payload.sub);

    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({
        ok: false,
        message: 'Token de acceso inválido',
      });
    }

    /*
      Guardamos la información autenticada.

      El role viene dentro del JWT generado
      durante el inicio de sesión.
    */
    req.auth = {
      userId,
      email: payload.email ?? null,
      role: payload.role ?? null,
    };

    return next();
  } catch (error) {
    const message =
      error?.name === 'TokenExpiredError'
        ? 'El token de acceso ha expirado'
        : 'Token de acceso inválido';

    return res.status(401).json({
      ok: false,
      message,
    });
  }
}

module.exports = authMiddleware;
