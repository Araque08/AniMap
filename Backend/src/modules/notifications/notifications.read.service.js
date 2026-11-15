
const db = require('../../config/postgres_db');

// =====================================================
// HU-071: MARCAR NOTIFICACIÓN COMO LEÍDA
// =====================================================

async function marcarNotificacionLeida(usuarioId, notificacionId) {
  const userId = Number(usuarioId);
  const notificationId = Number(notificacionId);

  // Validar identificadores.
  if (
    !Number.isInteger(userId) ||
    userId <= 0 ||
    !Number.isInteger(notificationId) ||
    notificationId <= 0
  ) {
    const error = new Error('Identificadores inválidos');
    error.statusCode = 400;
    throw error;
  }

  // Actualizar únicamente las notificaciones
  // pertenecientes al usuario autenticado.
  const resultado = await db.pool.query(
    `
    UPDATE notificacion
    SET leida = TRUE
    WHERE id = $1
      AND fk_usuario = $2
    RETURNING id, leida
    `,
    [notificationId, userId]
  );

  // No revelar si la notificación pertenece
  // a otro usuario o simplemente no existe.
  if (resultado.rowCount === 0) {
    const error = new Error('Notificación no encontrada');
    error.statusCode = 404;
    throw error;
  }

  return {
    id: resultado.rows[0].id,
    leida: resultado.rows[0].leida
  };
}

module.exports = {
  marcarNotificacionLeida
};
