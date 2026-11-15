
const { pool } = require('../../config/postgres_db');

const {
  createAdminDeliveryWorker
} = require('./admin-notifications.delivery.worker');

// =====================================================
// HU-049: PROGRAMADOR GENERAL DE COMUNICADOS
// =====================================================

function numeroValido(valor) {
  const texto = String(valor ?? '');

  if (!/^(0|[1-9]\d*)$/.test(texto)) {
    return false;
  }

  const numero = Number(texto);

  return Number.isSafeInteger(numero) &&
    numero <= 2147483647;
}

function createAdminGeneralScheduler({
  enabled = process.env.ADMIN_FCM_GENERAL_ENABLED,
  afterNotificationId =
    process.env.ADMIN_FCM_GENERAL_AFTER_ID,
  database = pool,
  workerFactory = createAdminDeliveryWorker,
  intervalMs = 30000,
  logger = console
} = {}) {

  let activo = false;
  let procesando = false;
  let timer = null;

  // ===================================================
  // PROCESAR ENTREGAS NUEVAS
  // ===================================================

  async function ejecutar() {
    if (!activo || procesando) return;

    procesando = true;

    try {
      const resultado = await database.query(
        `
        SELECT
          n.id AS notificacion_id,
          n.fk_usuario AS usuario_id

        FROM notificacion_entrega d

        INNER JOIN notificacion n
          ON n.id = d.fk_notificacion

        WHERE n.tipo = 'ADMINISTRATIVA'

          -- No procesar comunicados anteriores
          -- a la activación general.
          AND n.id > $1::integer

          AND d.intentos < 3

          AND (
            d.estado = 'PENDIENTE'

            OR (
              d.estado = 'REINTENTO'
              AND d.proximo_intento_en <=
                (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
            )

            OR (
              d.estado = 'EN_PROCESO'
              AND (
                d.iniciado_en IS NULL
                OR d.iniciado_en <
                  (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
                  - INTERVAL '15 minutes'
              )
            )
          )

        ORDER BY d.id ASC
        LIMIT 20
        `,
        [Number(afterNotificationId)]
      );

      for (const fila of resultado.rows) {
        if (!activo) break;

        // Reutilizar el procesador validado.
        // Cada ejecución queda limitada a un
        // usuario y una notificación específicos.
        const worker = workerFactory({
          enabled: 'true',
          qaUserId: String(fila.usuario_id),
          qaNotificationId:
            String(fila.notificacion_id),
        });

        try {
          const entrega =
            await worker.procesarUnaEntrega();

          if (
            entrega.estado !==
            'SIN_ENTREGAS_PENDIENTES'
          ) {
            logger.info?.(
              '[ADMIN_FCM] Notificacion:',
              fila.notificacion_id,
              'Resultado:',
              entrega.estado
            );
          }

        } catch (error) {
          logger.error?.(
            '[ADMIN_FCM] Error procesando notificacion:',
            fila.notificacion_id,
            error.code || error.message
          );
        }
      }

    } catch (error) {
      logger.error?.(
        '[ADMIN_FCM] Error consultando entregas:',
        error.code || error.message
      );

    } finally {
      procesando = false;
    }
  }

  // ===================================================
  // INICIAR
  // ===================================================

  function start() {
    if (activo) return true;

    if (enabled !== 'true') {
      return false;
    }

    if (!numeroValido(afterNotificationId)) {
      logger.error?.(
        '[ADMIN_FCM] Bloqueado: falta el ID de corte.'
      );
      return false;
    }

    activo = true;

    // Comprobar entregas al iniciar.
    void ejecutar();

    // Revisar nuevas entregas cada 30 segundos.
    timer = setInterval(() => {
      void ejecutar();
    }, intervalMs);

    timer.unref?.();

    logger.info?.(
      '[ADMIN_FCM] Programador general iniciado.'
    );

    return true;
  }

  // ===================================================
  // DETENER
  // ===================================================

  function stop() {
    activo = false;

    if (timer) {
      clearInterval(timer);
      timer = null;
    }
  }

  return {
    start,
    stop,
    ejecutar
  };
}

module.exports = {
  createAdminGeneralScheduler
};
