
const {
  createAdminDeliveryWorker
} = require('./admin-notifications.delivery.worker');

// =====================================================
// HU-049: PROGRAMADOR DE ENTREGAS FCM
// =====================================================

function idValido(valor) {
  const texto = String(valor ?? '');

  if (!/^[1-9]\d*$/.test(texto)) {
    return false;
  }

  const numero = Number(texto);

  return Number.isSafeInteger(numero) &&
    numero <= 2147483647;
}

function createAdminQAScheduler({
  enabled = process.env.ADMIN_FCM_ENABLED,
  qaUserId = process.env.ADMIN_FCM_QA_USER_ID,
  qaNotificationId = process.env.ADMIN_FCM_QA_NOTIFICATION_ID,
  workerFactory = createAdminDeliveryWorker,
  intervalMs = 30000,
  logger = console
} = {}) {

  let timer = null;
  let activo = false;
  let procesando = false;
  let worker = null;

  // ===================================================
  // PROCESAR UNA ENTREGA SIN SOLAPAR EJECUCIONES
  // ===================================================

  async function ejecutar() {
    if (!activo || procesando) return;

    procesando = true;

    try {
      const resultado = await worker.procesarUnaEntrega();

      if (
        resultado?.estado &&
        resultado.estado !== 'SIN_ENTREGAS_PENDIENTES'
      ) {
        logger.info?.(
          '[ADMIN_FCM_QA] Resultado:',
          resultado.estado
        );
      }

    } catch (_) {
      logger.error?.(
        '[ADMIN_FCM_QA] Error de procesamiento. ' +
        'Revisar PostgreSQL antes de reintentar.'
      );

    } finally {
      procesando = false;
    }
  }

  // ===================================================
  // INICIAR PROGRAMADOR
  // ===================================================

  function start() {
    if (activo) return true;

    // Desactivado por defecto.
    if (enabled !== 'true') {
      return false;
    }

    // Impedir ejecuciones sin usuario y notificación QA.
    if (
      !idValido(qaUserId) ||
      !idValido(qaNotificationId)
    ) {
      logger.error?.(
        '[ADMIN_FCM_QA] Bloqueado: faltan IDs QA válidos.'
      );
      return false;
    }

    worker = workerFactory({
      enabled: 'true',
      qaUserId: String(qaUserId),
      qaNotificationId: String(qaNotificationId)
    });

    activo = true;

    // Procesar al iniciar.
    void ejecutar();

    // Revisar entregas pendientes cada 30 segundos.
    timer = setInterval(() => {
      void ejecutar();
    }, intervalMs);

    // El temporizador no impide apagar Node.js.
    timer.unref?.();

    logger.info?.(
      '[ADMIN_FCM_QA] Programador iniciado en modo de prueba.'
    );

    return true;
  }

  // ===================================================
  // DETENER PROGRAMADOR
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
  createAdminQAScheduler
};
