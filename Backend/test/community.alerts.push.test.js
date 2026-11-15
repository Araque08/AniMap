
const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createNotificationsService,
} = require('../src/modules/notifications/notifications.service');

test('HU-064: procesa una alerta comunitaria sin envío real', async () => {
  const sent = [];
  const completed = [];
  let claims = 0;

  const notification = {
    id: 100,
    recipientId: 76,
    reportId: 25,
    title: 'Mascota perdida cerca de ti',
    message: 'Se reportó una mascota perdida.',
  };

  const repo = {
    pool: {},

    recoverAbandoned: async () => [],
    recoverCommunityAbandoned: async () => [],
    pendingNotifications: async () => [],

    pendingCommunityAlerts: async () => [notification],

    listTargets: async () => [
      { id: 10, registrationId: 'registro-simulado' },
    ],

    planDeliveries: async () => {},

    claimDelivery: async () => {
      claims++;
      return claims === 1
        ? { id: 200, sessionId: 10, attempts: 1 }
        : null;
    },

    currentTarget: async () => ({
      registrationId: 'registro-simulado',
    }),

    finishDelivery: async (delivery, result) => {
      completed.push(result);
    },

    summarize: async () => {},
  };

  const communityRepo = {
    listEligibleRecipients: async () => [
      { userId: 76, distanceKm: 0.238 },
    ],
  };

  const sender = {
    send: async (payload) => {
      sent.push(payload);
      return 'projects/animapbd/messages/simulado';
    },
  };

  const service = createNotificationsService({
    repo,
    communityRepo,
    sender,
    enabled: true,
    communityEnabled: true,
    testMode: true,
    testOwnerId: 81,
    testReportId: 25,
    communityTestRecipientId: 76,
    communityTestReportId: 25,
  });

  await service.drain();

  assert.equal(sent.length, 1);
  assert.equal(sent[0].data.type, 'PERDIDA_CERCANA');
  assert.equal(sent[0].data.reportId, '25');
  assert.equal(completed[0].state, 'ACEPTADA_FCM');

  // Un segundo procesamiento no debe repetir
  // una entrega que ya fue reclamada.
  await service.drain();
  assert.equal(sent.length, 1);
});

test('HU-064: reintenta errores temporales sin duplicar entregas', async () => {
  let now = Date.parse('2026-11-11T12:00:00Z');
  let attempts = 0;
  let sends = 0;
  let state = 'PENDIENTE';
  let nextAt = now;

  const notification = {
    id: 100,
    recipientId: 76,
    reportId: 25,
    title: 'Mascota perdida cerca de ti',
    message: 'Se reportó una mascota perdida.',
  };

  const repo = {
    pool: {},
    recoverAbandoned: async () => [],
    recoverCommunityAbandoned: async () => [],
    pendingNotifications: async () => [],
    pendingCommunityAlerts: async () => [notification],

    listTargets: async () => [
      { id: 10, registrationId: 'registro-simulado' },
    ],

    planDeliveries: async () => {},

    claimDelivery: async () => {
      if (
        attempts >= 3 ||
        now < nextAt ||
        !['PENDIENTE', 'REINTENTO'].includes(state)
      ) {
        return null;
      }

      state = 'EN_PROCESO';
      attempts++;

      return {
        id: 200,
        sessionId: 10,
        attempts,
      };
    },

    currentTarget: async () => ({
      registrationId: 'registro-simulado',
    }),

    finishDelivery: async (_delivery, result) => {
      state = result.state;
      nextAt = result.nextAt
        ? Date.parse(result.nextAt)
        : Infinity;
    },

    summarize: async () => {},
  };

  const communityRepo = {
    listEligibleRecipients: async () => [
      { userId: 76, distanceKm: 0.238 },
    ],
  };

  const sender = {
    send: async () => {
      sends++;

      // Simular dos errores temporales de Firebase.
      if (sends <= 2) {
        const error = new Error('Error simulado');
        error.code = 'messaging/server-unavailable';
        throw error;
      }

      // El tercer intento es exitoso.
      return 'projects/animapbd/messages/simulado';
    },
  };

  const service = createNotificationsService({
    repo,
    communityRepo,
    sender,
    enabled: true,
    communityEnabled: true,
    testMode: true,
    testOwnerId: 81,
    testReportId: 25,
    communityTestRecipientId: 76,
    communityTestReportId: 25,
    now: () => now,
    random: () => 0,
  });

  // Primer intento: falla.
  await service.drain();
  assert.equal(state, 'REINTENTO');
  assert.equal(sends, 1);
  assert.equal(nextAt, now + 60000);

  // No debe reintentar antes del plazo.
  await service.drain();
  assert.equal(sends, 1);

  // Segundo intento: vuelve a fallar.
  now += 60000;
  await service.drain();
  assert.equal(state, 'REINTENTO');
  assert.equal(sends, 2);
  assert.equal(nextAt, now + 120000);

  // Tercer intento: Firebase acepta el mensaje.
  now += 120000;
  await service.drain();
  assert.equal(state, 'ACEPTADA_FCM');
  assert.equal(sends, 3);

  // No repetir un envío ya aceptado.
  await service.drain();
  assert.equal(sends, 3);
  assert.equal(attempts, 3);
});

test('HU-064: recupera una entrega interrumpida sin reenviarla', async () => {
  const notificationId = 100;

  let deliveryState = 'EN_PROCESO';
  let summarizedId = null;
  let sends = 0;

  const repo = {
    pool: {},

    recoverAbandoned: async () => [],
    pendingNotifications: async () => [],

    // Simular la recuperación de una entrega interrumpida.
    recoverCommunityAbandoned: async (scope) => {
      assert.deepEqual(scope, {
        recipientId: 76,
        reportId: 25,
      });

      deliveryState = 'INDETERMINADA';

      return [notificationId];
    },

    summarize: async (id) => {
      summarizedId = id;
    },

    // No debe volver a aparecer entre las pendientes.
    pendingCommunityAlerts: async () => [],
  };

  const sender = {
    send: async () => {
      sends++;
      throw new Error('No debe reenviarse');
    },
  };

  const service = createNotificationsService({
    repo,
    communityRepo: {
      listEligibleRecipients: async () => [],
    },
    sender,
    enabled: true,
    communityEnabled: true,
    testMode: true,
    testOwnerId: 81,
    testReportId: 25,
    communityTestRecipientId: 76,
    communityTestReportId: 25,
  });

  await service.drain();

  assert.equal(deliveryState, 'INDETERMINADA');
  assert.equal(summarizedId, notificationId);
  assert.equal(sends, 0);
});
