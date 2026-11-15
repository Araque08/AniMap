
const {
  obtenerHistorialNotificaciones
} = require('./notifications.history.service');

const {
  marcarNotificacionLeida
} = require('./notifications.read.service');

// =====================================================
// HU-070: CONSULTAR HISTORIAL DE NOTIFICACIONES
// =====================================================

async function listarNotificaciones(req, res, next) {
  try {
    const usuarioId = req.auth.userId;
    const pagina = req.query.pagina ?? 1;

    const resultado = await obtenerHistorialNotificaciones(
      usuarioId,
      pagina
    );

    return res.status(200).json({
      ok: true,
      message: 'Historial de notificaciones consultado correctamente',
      data: resultado
    });

  } catch (error) {
    return next(error);
  }
}

// =====================================================
// HU-071: MARCAR NOTIFICACIÓN COMO LEÍDA
// =====================================================

async function marcarComoLeida(req, res, next) {
  try {
    // Obtenemos el usuario de la sesión autenticada.
    const usuarioId = req.auth.userId;

    // Obtenemos el ID de la notificación desde la URL.
    const notificacionId = req.params.id;

    // Actualizamos el estado en PostgreSQL.
    const resultado = await marcarNotificacionLeida(
      usuarioId,
      notificacionId
    );

    return res.status(200).json({
      ok: true,
      message: 'Notificación marcada como leída correctamente',
      data: resultado
    });

  } catch (error) {
    return next(error);
  }
}

module.exports = {
  listarNotificaciones,
  marcarComoLeida
};
