
const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createAdminGeneralScheduler
} = require(
  '../src/modules/admin-notifications/admin-notifications.delivery.general.scheduler'
);

const logger = {
  info() {},
  error() {}
};

// ================================================
// PRUEBA 1: DESACTIVADO
// ================================================

test('No consulta ni envia cuando esta desactivado', async () => {
  let consultas = 0;

  const scheduler = createAdminGeneralScheduler({
    enabled: 'false',
    afterNotificationId: '17',
    logger,
    database: {
      async query() {
        consultas++;
        return { rows: [] };
      }
    }
  });

  assert.equal(scheduler.start(), false);

  await scheduler.ejecutar();

  assert.equal(consultas, 0);
});

// ================================================
// PRUEBA 2: ID DE CORTE OBLIGATORIO
// ================================================

test('No inicia sin un ID de corte valido', () => {
  const scheduler = createAdminGeneralScheduler({
    enabled: 'true',
    afterNotificationId: '',
    logger
  });

  assert.equal(scheduler.start(), false);
});

// ================================================
// PRUEBA 3: SOLO NOTIFICACIONES POSTERIORES
// ================================================

test('Consulta y procesa con el ID de corte correcto', async () => {
  let consultaSQL = '';
  let parametrosSQL = [];
  const procesadas = [];

  const scheduler = createAdminGeneralScheduler({
    enabled: 'true',
    afterNotificationId: '17',
    intervalMs: 60000,
    logger,

    database: {
      async query(sql, parametros) {
        consultaSQL = sql;
        parametrosSQL = parametros;

        return {
          rows: [
            {
              notificacion_id: 18,
              usuario_id: 76
            }
          ]
        };
      }
    },

    workerFactory: configuracion => ({
      async procesarUnaEntrega() {
        procesadas.push(configuracion);

        return {
          estado: 'ACEPTADA_FCM'
        };
      }
    })
  });

  try {
    assert.equal(scheduler.start(), true);

    // Permitir que termine la ejecución inicial.
    await new Promise(resolve => setImmediate(resolve));

    assert.ok(
      consultaSQL.includes('n.id > $1::integer')
    );

    assert.deepEqual(parametrosSQL, [17]);

    assert.equal(procesadas.length, 1);

    assert.equal(procesadas[0].qaUserId, '76');
    assert.equal(procesadas[0].qaNotificationId, '18');

  } finally {
    scheduler.stop();
  }
});

// ================================================
// PRUEBA 4: EVITAR EJECUCIONES SIMULTANEAS
// ================================================

test('No ejecuta dos procesamientos simultaneos', async () => {
  let consultas = 0;
  let finalizar;

  const operacionPendiente = new Promise(resolve => {
    finalizar = resolve;
  });

  const scheduler = createAdminGeneralScheduler({
    enabled: 'true',
    afterNotificationId: '17',
    intervalMs: 60000,
    logger,

    database: {
      async query() {
        consultas++;

        await operacionPendiente;

        return { rows: [] };
      }
    }
  });

  try {
    assert.equal(scheduler.start(), true);

    await scheduler.ejecutar();
    await scheduler.ejecutar();

    assert.equal(consultas, 1);

  } finally {
    finalizar();
    scheduler.stop();
  }
});
