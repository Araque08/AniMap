function requireRole(...allowedRoles) {
  const allowed = new Set(allowedRoles.map((role) => String(role).trim().toUpperCase()));
  return (req, res, next) => {
    if (!req.auth) {
      return res.status(401).json({ ok: false, code: 'ACCESS_TOKEN_REQUIRED', message: 'Autenticación requerida' });
    }
    if (!allowed.has(req.auth.role)) {
      return res.status(403).json({ ok: false, code: 'ROLE_FORBIDDEN', message: 'No tienes permisos para realizar esta acción' });
    }
    return next();
  };
}

module.exports = requireRole;
