
const {
  obtenerResumenAudiencias,
  enviarNotificacionAdministrativa
} = require('./admin-notifications.service');

const {
  BARRIOS_NOTIFICACIONES
} = require('../notification-preferences/notification-preferences.schemas');

// =====================================================
// CONSULTAR AUDIENCIAS Y BARRIOS
// =====================================================

async function listarAudiencias(req, res, next) {
  try {
    const barrio = req.query.barrio ?? null;

    const resumen = await obtenerResumenAudiencias(barrio);

    return res.status(200).json({
      ok: true,
      message: 'Audiencias consultadas correctamente',
      data: {
        barrioSeleccionado: barrio,

        // Catálogo para el formulario administrativo.
        barrios: BARRIOS_NOTIFICACIONES,

        // Cantidades filtradas por el barrio consultado.
        audiencias: [
          {
            codigo: 'TODOS',
            nombre: 'Todos los usuarios',
            total: Number(resumen.todos)
          },
          {
            codigo: 'USUARIO',
            nombre: 'Usuarios',
            total: Number(resumen.usuarios)
          },
          {
            codigo: 'ADMINISTRADOR',
            nombre: 'Administradores',
            total: Number(resumen.administradores)
          }
        ]
      }
    });

  } catch (error) {
    return next(error);
  }
}

// =====================================================
// REGISTRAR COMUNICADO ADMINISTRATIVO
// =====================================================

async function enviarComunicado(req, res, next) {
  try {
    const administradorId = req.auth.userId;

    const {
      titulo,
      mensaje,
      audiencia,
      barrio
    } = req.validatedBody;

    const resultado = await enviarNotificacionAdministrativa({
      administradorId,
      titulo,
      mensaje,
      audiencia,
      barrio: barrio ?? null
    });

    return res.status(201).json({
      ok: true,
      message: 'Comunicado registrado correctamente en AniMap',
      data: resultado
    });

  } catch (error) {
    return next(error);
  }
}

module.exports = {
  listarAudiencias,
  enviarComunicado
};
