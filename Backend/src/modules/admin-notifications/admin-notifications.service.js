
const db = require('../../config/postgres_db');

const {
  BARRIOS_NOTIFICACIONES
} = require('../notification-preferences/notification-preferences.schemas');

const {
  planificarEntregas
} = require('./admin-notifications.delivery.repository');

// =====================================================
// HU-049: AUDIENCIAS DISPONIBLES
// =====================================================

const AUDIENCIAS = [
  'TODOS',
  'USUARIO',
  'ADMINISTRADOR'
];

// =====================================================
// VALIDACIONES
// =====================================================

function errorHttp(mensaje, codigo = 400) {
  const error = new Error(mensaje);
  error.statusCode = codigo;
  return error;
}

function validarAudiencia(audiencia) {
  if (!AUDIENCIAS.includes(audiencia)) {
    throw errorHttp('Audiencia no válida');
  }

  return audiencia;
}

function validarBarrio(barrio) {
  // No seleccionar barrio significa enviar por rol,
  // sin restricción geográfica adicional.
  if (barrio === null || barrio === undefined || barrio === '') {
    return null;
  }

  if (
    typeof barrio !== 'string' ||
    !BARRIOS_NOTIFICACIONES.includes(barrio)
  ) {
    throw errorHttp('Barrio no válido');
  }

  return barrio;
}

// =====================================================
// CONSULTAR DESTINATARIOS
// =====================================================

async function obtenerDestinatarios(
  audiencia,
  barrio = null
) {
  validarAudiencia(audiencia);
  const barrioValidado = validarBarrio(barrio);

  const resultado = await db.query(
    `
    SELECT DISTINCT u.id AS usuario_id
    FROM usuario u

    INNER JOIN usuario_rol ur
      ON ur.fk_usuario = u.id

    INNER JOIN rol r
      ON r.id = ur.fk_rol

    INNER JOIN perfil p
      ON p.fk_usuario = u.id

    WHERE u.estado_cuenta = 'ACTIVO'
      AND u.is_verified = TRUE
      AND p.notificaciones_activas = TRUE

      AND (
        $1::text = 'TODOS'
        OR r.nombre = $1::text
      )

      AND (
        $2::varchar(100) IS NULL
        OR p.barrio_notificaciones = $2::varchar(100)
      )

    ORDER BY u.id
    `,
    [audiencia, barrioValidado]
  );

  return resultado.rows.map(
    fila => Number(fila.usuario_id)
  );
}

// =====================================================
// RESUMEN DE AUDIENCIAS POR BARRIO
// =====================================================

async function obtenerResumenAudiencias(barrio = null) {
  const barrioValidado = validarBarrio(barrio);

  const resultado = await db.query(
    `
    SELECT
      COUNT(DISTINCT u.id)::int AS todos,

      COUNT(DISTINCT u.id) FILTER (
        WHERE r.nombre = 'USUARIO'
      )::int AS usuarios,

      COUNT(DISTINCT u.id) FILTER (
        WHERE r.nombre = 'ADMINISTRADOR'
      )::int AS administradores

    FROM usuario u

    INNER JOIN usuario_rol ur
      ON ur.fk_usuario = u.id

    INNER JOIN rol r
      ON r.id = ur.fk_rol

    INNER JOIN perfil p
      ON p.fk_usuario = u.id

    WHERE u.estado_cuenta = 'ACTIVO'
      AND u.is_verified = TRUE
      AND p.notificaciones_activas = TRUE

      AND (
        $1::varchar(100) IS NULL
        OR p.barrio_notificaciones = $1::varchar(100)
      )
    `,
    [barrioValidado]
  );

  return resultado.rows[0];
}

// =====================================================
// GUARDAR COMUNICADO ADMINISTRATIVO
// =====================================================

async function enviarNotificacionAdministrativa({
  administradorId,
  titulo,
  mensaje,
  audiencia,
  barrio = null
}) {
  const adminId = Number(administradorId);

  if (!Number.isInteger(adminId) || adminId <= 0) {
    throw errorHttp('Administrador inválido');
  }

  if (
    typeof titulo !== 'string' ||
    titulo.trim().length < 3 ||
    titulo.trim().length > 140
  ) {
    throw errorHttp(
      'El título debe contener entre 3 y 140 caracteres'
    );
  }

  if (
    typeof mensaje !== 'string' ||
    mensaje.trim().length < 5 ||
    mensaje.trim().length > 1000
  ) {
    throw errorHttp(
      'El mensaje debe contener entre 5 y 1000 caracteres'
    );
  }

  validarAudiencia(audiencia);
  const barrioValidado = validarBarrio(barrio);

  const client = await db.pool.connect();

  try {
    await client.query('BEGIN');

    // =================================================
    // GUARDAR UNA NOTIFICACIÓN POR DESTINATARIO
    // =================================================

    const resultado = await client.query(
      `
      INSERT INTO notificacion (
        fk_usuario,
        fk_reporte,
        titulo,
        mensaje,
        leida,
        fecha,
        tipo,
        estado_envio,
        audiencia
      )

      SELECT DISTINCT
        u.id,
        NULL::integer,
        $2,
        $3,
        FALSE,
        CURRENT_TIMESTAMP AT TIME ZONE 'UTC',
        'ADMINISTRATIVA',
        NULL,
        $1

      FROM usuario u

      INNER JOIN usuario_rol ur
        ON ur.fk_usuario = u.id

      INNER JOIN rol r
        ON r.id = ur.fk_rol

      INNER JOIN perfil p
        ON p.fk_usuario = u.id

      WHERE u.estado_cuenta = 'ACTIVO'
        AND u.is_verified = TRUE
        AND p.notificaciones_activas = TRUE

        AND (
          $1::text = 'TODOS'
          OR r.nombre = $1::text
        )

        AND (
          $4::varchar(100) IS NULL
          OR p.barrio_notificaciones = $4::varchar(100)
        )

      RETURNING id, fk_usuario
      `,
      [
        audiencia,
        titulo.trim(),
        mensaje.trim(),
        barrioValidado
      ]
    );

    const totalGuardadas = resultado.rowCount;

    if (totalGuardadas === 0) {
      throw errorHttp(
        'No hay destinatarios habilitados para esta audiencia y barrio',
        422
      );
    }


    // =================================================
    // HU-049: PLANIFICAR ENTREGAS FIREBASE
    // =================================================

    // Los registros se crean dentro de la misma
    // transacción que las notificaciones internas.
    //
    // Todavía NO se llama a Firebase.

    const notificacionIds = resultado.rows.map(
      fila => Number(fila.id)
    );

    const entregasPendientesFCM = await planificarEntregas(
      client,
      notificacionIds
    );

    // =================================================
    // REGISTRAR AUDITORÍA
    // =================================================

    const detalle = {
      titulo: titulo.trim(),
      audiencia,
      barrio: barrioValidado,
      destinatarios: totalGuardadas,
      guardadasEnHistorial: totalGuardadas,
      fallidas: 0,
      canal: 'INTERNO',
      estado: 'REGISTRADO_EN_APP',
      pushEnviado: false,
      notificacionIds,
      entregasPendientesFCM,
      entregasAceptadasFCM: 0,
      entregasFallidasFCM: 0
    };

    const auditoria = await client.query(
      `
      INSERT INTO bitacora_administrativa (
        fk_admin,
        modulo,
        accion,
        entidad_afectada,
        id_entidad_afectada,
        detalle,
        fecha_hora
      )
      VALUES (
        $1,
        'NOTIFICACIONES',
        'ENVIO_ADMINISTRATIVO',
        'notificacion',
        $2,
        $3,
        CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
      )
      RETURNING id, fecha_hora
      `,
      [
        adminId,
        resultado.rows[0].id,
        JSON.stringify(detalle)
      ]
    );

    await client.query('COMMIT');

    return {
      auditoriaId: auditoria.rows[0].id,
      fecha: auditoria.rows[0].fecha_hora,
      audiencia,
      barrio: barrioValidado,
      totalDestinatarios: totalGuardadas,
      guardadasEnHistorial: totalGuardadas,
      fallidas: 0,
      estado: 'REGISTRADO_EN_APP',
      pushEnviado: false,
      entregasPendientesFCM,
      entregasAceptadasFCM: 0,
      entregasFallidasFCM: 0
    };

  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;

  } finally {
    client.release();
  }
}

module.exports = {
  obtenerDestinatarios,
  obtenerResumenAudiencias,
  enviarNotificacionAdministrativa
};
