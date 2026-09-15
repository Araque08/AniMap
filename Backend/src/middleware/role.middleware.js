/*
  Middleware de autorización por rol.

  Debe utilizarse después de authMiddleware.

  Ejemplo:

  router.post(
    '/faqs',
    authMiddleware,
    requireRole('ADMINISTRADOR'),
    controller.createFaq
  );
*/

function requireRole(...allowedRoles) {
  /*
    Normalizamos los roles permitidos para evitar
    problemas por mayúsculas o espacios.
  */
  const normalizedRoles = allowedRoles.map((role) =>
    String(role).trim().toUpperCase()
  );

  return function roleMiddleware(req, res, next) {
    /*
      authMiddleware debe ejecutarse primero.
    */
    if (!req.auth) {
      return res.status(401).json({
        ok: false,
        message: 'Autenticación requerida',
      });
    }

    const userRole = String(
      req.auth.role ?? ''
    )
      .trim()
      .toUpperCase();

    /*
      Si el token no contiene un rol válido,
      no permitimos continuar.
    */
    if (!userRole) {
      return res.status(403).json({
        ok: false,
        message: 'El usuario no tiene un rol válido',
      });
    }

    /*
      Comprobamos que el rol del usuario esté
      dentro de los roles permitidos.
    */
    if (!normalizedRoles.includes(userRole)) {
      return res.status(403).json({
        ok: false,
        message: 'No tienes permisos para realizar esta acción',
      });
    }

    return next();
  };
}

module.exports = requireRole;