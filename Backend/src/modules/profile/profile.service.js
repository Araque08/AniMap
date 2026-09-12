const db = require('../../config/postgres_db');

function createHttpError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

async function getProfile(userId) {
  const result = await db.query(
    `
      SELECT
        u.id,
        u.nombre,
        u.email,
        u.telefono,
        p.foto_url,
        p.notificaciones_activas
      FROM usuario u
      INNER JOIN perfil p ON p.fk_usuario = u.id
      WHERE u.id = $1
      LIMIT 1
    `,
    [userId]
  );

  if (result.rowCount === 0) {
    throw createHttpError('Perfil no encontrado', 404);
  }

  return result.rows[0];
}

async function updateProfile(userId, data) {
  const result = await db.query(
    `
      UPDATE usuario
      SET
        nombre = COALESCE($2, nombre),
        telefono = COALESCE($3, telefono)
      WHERE id = $1
      RETURNING id
    `,
    [userId, data.nombre ?? null, data.telefono ?? null]
  );

  if (result.rowCount === 0) {
    throw createHttpError('Perfil no encontrado', 404);
  }

  return getProfile(userId);
}

module.exports = {
  getProfile,
  updateProfile,
};
