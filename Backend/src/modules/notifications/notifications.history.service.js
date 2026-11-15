
const db = require('../../config/postgres_db');

const PAGE_SIZE = 20;

// Consulta el historial del usuario autenticado.
async function obtenerHistorialNotificaciones(usuarioId, pagina = 1) {
  const userId = Number(usuarioId);
  const page = Number(pagina);

  if (!Number.isInteger(userId) || userId <= 0) {
    const error = new Error('Usuario inválido');
    error.statusCode = 400;
    throw error;
  }

  if (!Number.isInteger(page) || page < 1 || page > 100000) {
    const error = new Error('Página inválida');
    error.statusCode = 400;
    throw error;
  }

  const offset = (page - 1) * PAGE_SIZE;

  const resultado = await db.pool.query(
    `
    SELECT
      id,
      titulo,
      mensaje,
      COALESCE(tipo, 'SISTEMA') AS tipo,
      leida,
      (fecha AT TIME ZONE 'UTC') AS fecha,
      fk_reporte AS "reporteId",
      fk_avistamiento AS "avistamientoId"
    FROM notificacion
    WHERE fk_usuario = $1
      AND (
        estado_envio IS NULL
        OR estado_envio IN (
          'ACEPTADA_FCM',
          'PARCIAL',
          'PARCIAL_FINAL',
          'ENVIADA',
          'ENTREGADA'
        )
      )
    ORDER BY fecha DESC, id DESC
    LIMIT $2 OFFSET $3
    `,
    [userId, PAGE_SIZE + 1, offset]
  );

  return {
    notificaciones: resultado.rows.slice(0, PAGE_SIZE),
    pagina: page,
    hayMas: resultado.rows.length > PAGE_SIZE
  };
}

module.exports = {
  obtenerHistorialNotificaciones
};
