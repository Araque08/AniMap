const ALLOWED_ROLES = new Set(['USUARIO', 'ADMINISTRADOR']);

async function getSingleRole(client, userId) {
  const result = await client.query(
    `SELECT r.nombre
     FROM usuario_rol ur
     INNER JOIN rol r ON r.id = ur.fk_rol
     WHERE ur.fk_usuario = $1`,
    [userId]
  );
  const roles = result.rows.map((row) => String(row.nombre || '').trim().toUpperCase());
  if (roles.length !== 1 || !ALLOWED_ROLES.has(roles[0])) {
    const error = new Error('La cuenta no tiene un único rol válido asignado');
    error.statusCode = 403;
    error.code = 'ACCOUNT_ROLE_INVALID';
    throw error;
  }
  return roles[0];
}

module.exports = { getSingleRole };
