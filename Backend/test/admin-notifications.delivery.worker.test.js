
const test = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');

const {
  createAdminDeliveryWorker
} = require('../src/modules/admin-notifications/admin-notifications.delivery.worker');

const AHORA = Date.parse('2026-11-05T14:00:00Z');

// =====================================================
// SIMULADOR DE POSTGRESQL Y FIREBASE
// =====================================================

function crearSimulador({
  hayPendiente = true,
  dispositivoValido = true,
  codigoError = null,
  intentos = 1,
  rolValido = true,
  comunicadoValido = true
  } = {}) {

  const consultas = [];
  const envios = [];

  const fid = 'FID_FICTICIO_SOLO_PARA_PRUEBAS';

  const huella = createHash('sha256')
    .update(fid)
    .digest('hex');

  let reclamado = false;

  const pool = {
    async query(sql, parametros = []) {
              // Simular los comandos transaccionales.
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql.trim())) {
        consultas.push({ sql, parametros });

        return {
          rowCount: 0,
          rows: []
        };
      }
      consultas.push({ sql, parametros });

      // Reclamar una entrega pendiente.
      if (sql.includes('WITH candidata AS')) {
        if (!hayPendiente || reclamado) {
          return {
            rowCount: 0,
            rows: []
          };
        }

        reclamado = true;

        return {
          rowCount: 1,
          rows: [{
            id: 99,
            intentos,
            registro_huella: huella
          }]
        };
      }

      // Consultar la notificación y el dispositivo.

      if (sql.includes('SELECT') &&
          sql.includes('ds.fcm_registration_id AS fid')) {
        return {
          rowCount: 1,
          rows: [{
            id: 101,
            titulo: 'Prueba HU-049',
            mensaje: 'Notificación administrativa de prueba.',
            fid,
            vigente: dispositivoValido,
            sesion_valida: dispositivoValido,
            cuenta_valida: dispositivoValido,
            notificaciones_activas: dispositivoValido,
            rol_autorizado: rolValido,
            comunicado_autorizado: comunicadoValido
          }]
        };
}

      // Actualizar el resultado de la entrega.
      if (sql.includes('UPDATE notificacion_entrega') &&
          sql.includes('SET')) {
        return {
            rowCount: 1,
            rows: [{
                id: 99,
                fk_notificacion: 101
            }]
        };
      }

      // Simular actualización de auditoría.
        if (sql.includes('WITH auditoria AS') &&
            sql.includes('UPDATE bitacora_administrativa')) {
        return {
            rowCount: 1,
            rows: [{ id: 113 }]
        };
        }

      throw new Error(
        'Consulta inesperada en la prueba aislada'
      );
        },

    // Simular una conexión dedicada para transacciones.
        async connect() {
        return {
            query: (sql, parametros) =>
            pool.query(sql, parametros),

            release() {}
        };
        }
    };

    const sender = {
    async send(datos) {
      envios.push(datos);

      if (codigoError) {
        const error = new Error('Error simulado');
        error.code = codigoError;
        throw error;
      }

      return 'projects/animapbd/messages/simulacion';
    }
  };

  const worker = createAdminDeliveryWorker({
    pool,
    sender,
    enabled: 'true',
    qaUserId: '76',
    qaNotificationId: '101',
    now: () => AHORA,
    random: () => 0
  });

  return {
    worker,
    pool,
    sender,
    consultas,
    envios
  };
}

// =====================================================
// PRUEBA 1: PROCESADOR DESHABILITADO
// =====================================================

test('No procesa entregas si está deshabilitado', async () => {
  const sim = crearSimulador();

  const worker = createAdminDeliveryWorker({
    pool: sim.pool,
    sender: sim.sender,
    enabled: 'false',
    qaUserId: '76',
    qaNotificationId: '101'
  });

  const resultado = await worker.procesarUnaEntrega();

  assert.equal(resultado.estado, 'DESHABILITADO');
  assert.equal(sim.consultas.length, 0);
  assert.equal(sim.envios.length, 0);
});

// =====================================================
// PRUEBA 2: CONFIGURACIÓN QA INCOMPLETA
// =====================================================

test('Bloquea una prueba sin IDs QA válidos', async () => {
  const sim = crearSimulador();

  const worker = createAdminDeliveryWorker({
    pool: sim.pool,
    sender: sim.sender,
    enabled: 'true',
    qaUserId: '76',
    qaNotificationId: undefined
  });

  await assert.rejects(
    worker.procesarUnaEntrega(),
    /Configuración QA incompleta/
  );

  assert.equal(sim.consultas.length, 0);
  assert.equal(sim.envios.length, 0);
});

// =====================================================
// PRUEBA 3: ENTREGA EXITOSA
// =====================================================

test('Registra una entrega aceptada por Firebase', async () => {
  const sim = crearSimulador();

  const resultado = await sim.worker.procesarUnaEntrega();

  assert.equal(resultado.estado, 'ACEPTADA_FCM');
  assert.equal(sim.envios.length, 1);

  assert.equal(
    sim.envios[0].notification.title,
    'Prueba HU-049'
  );

  assert.equal(
    sim.envios[0].data.type,
    'ADMINISTRATIVA'
  );

  const actualizacion = sim.consultas.findLast(
  consulta =>
    consulta.sql.includes('UPDATE notificacion_entrega') &&
    consulta.sql.includes('RETURNING')
);

  assert.equal(
    actualizacion.parametros[2],
    'ACEPTADA_FCM'
  );
});

// =====================================================
// PRUEBA 4: ERROR TEMPORAL
// =====================================================

test('Programa reintento ante error temporal', async () => {
  const sim = crearSimulador({
    codigoError: 'messaging/server-unavailable'
  });

  const resultado = await sim.worker.procesarUnaEntrega();

  assert.equal(resultado.estado, 'REINTENTO');

  const actualizacion = sim.consultas.findLast(
  consulta =>
    consulta.sql.includes('UPDATE notificacion_entrega') &&
    consulta.sql.includes('RETURNING')
    );

  assert.equal(actualizacion.parametros[2], 'REINTENTO');

  const proximoIntento = actualizacion.parametros[4];

  assert.ok(
    Date.parse(proximoIntento) > AHORA
  );

  assert.equal(sim.envios.length, 1);
});

// =====================================================
// PRUEBA 5: DISPOSITIVO NO DISPONIBLE
// =====================================================

test('Omite dispositivos sin sesión válida', async () => {
  const sim = crearSimulador({
    dispositivoValido: false
  });

  const resultado = await sim.worker.procesarUnaEntrega();

  assert.equal(resultado.estado, 'OMITIDA');
  assert.equal(sim.envios.length, 0);

  const actualizacion = sim.consultas.findLast(
  consulta =>
    consulta.sql.includes('UPDATE notificacion_entrega') &&
    consulta.sql.includes('RETURNING')
    );

  assert.equal(
    actualizacion.parametros[3],
    'DESTINATARIO_NO_DISPONIBLE'
  );
});

// =====================================================
// PRUEBA 6: SIN ENTREGAS PENDIENTES
// =====================================================

test('No envía mensajes si no existen pendientes', async () => {
  const sim = crearSimulador({
    hayPendiente: false
  });

  const resultado = await sim.worker.procesarUnaEntrega();

  assert.equal(
    resultado.estado,
    'SIN_ENTREGAS_PENDIENTES'
  );

  assert.equal(sim.envios.length, 0);
});

// =====================================================
// PRUEBA 7: EVITAR PROCESAR DOS VECES
// =====================================================

test('No vuelve a reclamar una entrega procesada', async () => {
  const sim = crearSimulador();

  const primera = await sim.worker.procesarUnaEntrega();

  const segunda = await sim.worker.procesarUnaEntrega();

  assert.equal(primera.estado, 'ACEPTADA_FCM');

  assert.equal(
    segunda.estado,
    'SIN_ENTREGAS_PENDIENTES'
  );

  assert.equal(sim.envios.length, 1);
});

// =====================================================
// PRUEBA 8: RESULTADO INDETERMINADO
// =====================================================

test('No reintenta automáticamente un resultado incierto', async () => {
  const sim = crearSimulador({
    codigoError: 'app/network-timeout'
  });

  const resultado = await sim.worker.procesarUnaEntrega();

  assert.equal(resultado.estado, 'INDETERMINADA');

  const actualizacion = sim.consultas.findLast(
  consulta =>
    consulta.sql.includes('UPDATE notificacion_entrega') &&
    consulta.sql.includes('RETURNING')
    );

  assert.equal(
    actualizacion.parametros[4],
    null
  );

  assert.equal(sim.envios.length, 1);

// =====================================================
// PRUEBA 9: RECUPERACIÓN SEGURA
// =====================================================

test(
  'Revisa entregas interrumpidas sin reenviar mensajes',
  async () => {
    const sim = crearSimulador({
      hayPendiente: false
    });

    const resultado =
      await sim.worker.procesarUnaEntrega();

    // No existe una entrega pendiente para enviar.
    assert.equal(
      resultado.estado,
      'SIN_ENTREGAS_PENDIENTES'
    );

    // Verificar que se ejecutó la recuperación.
    const recuperacion = sim.consultas.find(
      consulta =>
        consulta.sql.includes('PROCESS_INTERRUPTED')
    );

    assert.ok(recuperacion);

    // Debe limitarse a la notificación QA 101
    // del usuario autorizado 76.
    assert.deepEqual(
      recuperacion.parametros,
      [101, 76]
    );

    // La consulta debe dejar las entregas antiguas
    // como indeterminadas, no pendientes.
    assert.ok(
      recuperacion.sql.includes(
        "estado = 'INDETERMINADA'"
      )
    );

    // No debe invocar Firebase.
    assert.equal(sim.envios.length, 0);
  }
);

// =====================================================
// PRUEBA 10: AUDITORÍA FIREBASE
// =====================================================

test(
  'Actualiza la auditoría después de finalizar la entrega',
  async () => {
    const sim = crearSimulador();

    const resultado =
      await sim.worker.procesarUnaEntrega();

    assert.equal(resultado.estado, 'ACEPTADA_FCM');

    const auditoria = sim.consultas.find(
      consulta =>
        consulta.sql.includes('WITH auditoria AS') &&
        consulta.sql.includes(
          'UPDATE bitacora_administrativa'
        )
    );

    assert.ok(
      auditoria,
      'Debe ejecutarse la actualización de auditoría'
    );

    assert.deepEqual(
      auditoria.parametros,
      [101]
    );

    assert.equal(sim.envios.length, 1);
  }
);


// =====================================================
// PRUEBA 11: ROLLBACK SI FALLA LA AUDITORÍA
// =====================================================

test(
  'Revierte la actualización si falla la auditoría',
  async () => {
    const sim = crearSimulador();

    const consultaOriginal = sim.pool.query.bind(sim.pool);

    // Simular que PostgreSQL rechaza la actualización
    // de la bitácora después de actualizar la entrega.
    sim.pool.query = async (sql, parametros) => {
      if (sql.includes('WITH auditoria AS')) {
        throw new Error('FALLO_AUDITORIA_SIMULADO');
      }

      return consultaOriginal(sql, parametros);
    };

    await assert.rejects(
      sim.worker.procesarUnaEntrega(),
      /FALLO_AUDITORIA_SIMULADO/
    );

    // Se debió iniciar una transacción.
    assert.ok(
      sim.consultas.some(
        consulta => consulta.sql.trim() === 'BEGIN'
      )
    );

    // Se debió solicitar la reversión.
    assert.ok(
      sim.consultas.some(
        consulta => consulta.sql.trim() === 'ROLLBACK'
      )
    );

    // No debe confirmarse una transacción incompleta.
    assert.equal(
      sim.consultas.some(
        consulta => consulta.sql.trim() === 'COMMIT'
      ),
      false
    );

    // La simulación realiza un único intento de envío.
    assert.equal(sim.envios.length, 1);
  }
);


// =====================================================
// PRUEBA 12: ROL REVOCADO
// =====================================================

test('No envia si el destinatario pierde el rol', async () => {
  const sim = crearSimulador({
    rolValido: false
  });

  const resultado = await sim.worker.procesarUnaEntrega();

  assert.equal(resultado.estado, 'OMITIDA');
  assert.equal(sim.envios.length, 0);
});

// =====================================================
// PRUEBA 13: COMUNICADO NO AUTORIZADO
// =====================================================

test('No envia si el barrio o la auditoria no coinciden', async () => {
  const sim = crearSimulador({
    comunicadoValido: false
  });

  const resultado = await sim.worker.procesarUnaEntrega();

  assert.equal(resultado.estado, 'OMITIDA');
  assert.equal(sim.envios.length, 0);
});

// =====================================================
// PRUEBA 14: RECUPERACION DE SESION FIREBASE
// =====================================================

test(
  'Revisa sesiones renovadas antes de procesar una entrega',
  async () => {
    const sim = crearSimulador();

    const resultado =
      await sim.worker.procesarUnaEntrega();

    const recuperacion = sim.consultas.find(
      consulta =>
        consulta.sql.includes(
          'WITH sesiones_actualizadas AS'
        )
    );

    assert.ok(
      recuperacion,
      'Debe revisar las sesiones renovadas'
    );

    assert.deepEqual(
      recuperacion.parametros,
      [101, 76]
    );

    // Solo puede actualizar entregas pendientes
    // que no tienen intentos anteriores.
    assert.ok(
      recuperacion.sql.includes(
        "d.estado = 'PENDIENTE'"
      )
    );

    assert.ok(
      recuperacion.sql.includes(
        'd.intentos = 0'
      )
    );

    // Debe conservar el mismo dispositivo.
    assert.ok(
      recuperacion.sql.includes(
        'nueva.device_id = anterior.device_id'
      )
    );

    assert.equal(resultado.estado, 'ACEPTADA_FCM');
    assert.equal(sim.envios.length, 1);
  }
);


});
