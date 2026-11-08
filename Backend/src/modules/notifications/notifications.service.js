const { createHash } = require('node:crypto');
const env = require('../../config/env');
const { createNotificationsRepository } = require('./notifications.repository');
const { createFirebaseSender, classifyFirebaseError } = require('./firebase.sender');

function coordinate(value, max) {
  return value !== null && value !== undefined && value !== ''
    && Number.isFinite(Number(value)) && Math.abs(Number(value)) <= max;
}

function skipReason(event) {
  if (!event) return 'EVENTO_NO_DISPONIBLE';
  if (!event.reportId) return 'SIN_REPORTE';
  if (event.reportState !== 'ACTIVO' || event.petState !== 'PERDIDA') return 'REPORTE_INACTIVO';
  if (event.authorId === event.ownerId) return 'AUTOR_PROPIETARIO';
  if (!event.ownerActive || !event.ownerVerified) return 'CUENTA_NO_DISPONIBLE';
  if (event.notificationsEnabled !== true) return 'NOTIFICACIONES_DESACTIVADAS';
  if (event.speciesFilter && event.speciesFilter.trim().toLowerCase() !== event.species?.trim().toLowerCase()) return 'FILTRO_ESPECIE';
  if (event.eventFilter && event.eventFilter !== 'AVISTAMIENTO') return 'FILTRO_TIPO';
  if (event.onlyMyZone) {
    if (!coordinate(event.lostLat, 90) || !coordinate(event.lostLng, 180)
      || !coordinate(event.lat, 90) || !coordinate(event.lng, 180)) return 'ZONA_SIN_COORDENADAS';
    if (event.radiusKm === null || event.radiusKm === undefined
      || !Number.isFinite(Number(event.radiusKm)) || Number(event.radiusKm) < 0) return 'ZONA_RADIO_INVALIDO';
    // Provisional origin approved for ANIMAP-35: original loss point, not user GPS.
    const radians = n => Number(n) * Math.PI / 180;
    const a = Math.sin(radians(event.lat - event.lostLat) / 2) ** 2
      + Math.cos(radians(event.lostLat)) * Math.cos(radians(event.lat))
      * Math.sin(radians(event.lng - event.lostLng) / 2) ** 2;
    const distance = 6371 * 2 * Math.asin(Math.sqrt(Math.min(1, a)));
    if (distance > Number(event.radiusKm)) return 'FUERA_RADIO';
  }
  return null;
}

function createNotificationsService({
  repo = createNotificationsRepository(), enabled = env.FCM_PUSH_ENABLED,
  testMode = env.FCM_TEST_MODE, testOwnerId = env.FCM_TEST_OWNER_ID,
  testReportId = env.FCM_TEST_REPORT_ID,
  processingMode = env.FCM_PROCESSING_MODE, budgetMs = 45000,
  sender = createFirebaseSender({ enabled }), now = Date.now, random = Math.random,
  logger = console,
} = {}) {
  // Snapshot configuration for this process. Invalid test settings must never
  // silently fall back to unrestricted production delivery.
  const testing = testMode !== false && testMode !== 'false';
  const validId = value => /^[1-9]\d*$/.test(String(value))
    && Number.isSafeInteger(Number(value)) && Number(value) <= 2147483647;
  const configured = !testing || ((testMode === true || testMode === 'true')
    && validId(testOwnerId) && validId(testReportId));
  const active = enabled === true && configured
    && ['inline', 'scheduled'].includes(processingMode);
  const scope = testing && configured
    ? Object.freeze({ ownerId: Number(testOwnerId), reportId: Number(testReportId) }) : null;
  const inScope = event => !scope || (event?.ownerId === scope.ownerId && event?.reportId === scope.reportId);
  let inFlight = null;
  let timer = null;
  let stopped = false;

  function warn(code, notificationId) {
    // Never include the caught error: PG/SDK errors may contain FIDs or credentials.
    logger.warn('AniMap push', { code, notificationId });
  }

  async function recordIntent(client, sightingId) {
    if (!active) return null;
    const event = await repo.loadEvent(client, sightingId);
    if (!inScope(event)) return null;
    if (!event?.reportId || !event.ownerId || event.authorId === event.ownerId) return null;
    return repo.insertIntent(client, event, skipReason(event));
  }

  async function deliver(notification, delivery) {
    const event = await repo.loadEvent(repo.pool, notification.sightingId);
    const reason = !inScope(event) ? 'FUERA_PRUEBA_FCM' : skipReason(event);
    if (reason || event.ownerId !== notification.ownerId) {
      await repo.finishDelivery(delivery, { state: 'OMITIDA', error: reason || 'DESTINATARIO_CAMBIO' });
      return;
    }
    const target = await repo.currentTarget(delivery, event.ownerId);
    if (!target) {
      await repo.finishDelivery(delivery, { state: 'OMITIDA', error: 'SESION_NO_DISPONIBLE' });
      return;
    }
    let result;
    try {
      const messageId = await sender.send({ fid: target.registrationId,
        notification: { title: 'Nuevo avistamiento de tu mascota',
          body: 'Registraron un avistamiento vinculado a tu reporte de pérdida.' },
        data: { type: 'AVISTAMIENTO_VINCULADO', notificationId: String(notification.id),
          sightingId: String(event.sightingId), reportId: String(event.reportId),
          ownerId: String(event.ownerId) },
        tag: `animap-notification-${notification.id}` });
      result = { state: 'ACEPTADA_FCM', messageId, acceptedAt: new Date(now()).toISOString() };
    } catch (error) {
      const failure = classifyFirebaseError(error, now());
      result = { state: failure.indeterminate ? 'INDETERMINADA' : 'FALLIDA_PERMANENTE', error: failure.code };
      if (failure.transient && delivery.attempts < 3) {
        const delay = Math.max(failure.retryAfterMs,
          60000 * 2 ** (delivery.attempts - 1) + Math.floor(random() * 10000));
        result = { state: 'REINTENTO', error: failure.code, nextAt: new Date(now() + delay).toISOString() };
      }
      if (failure.invalidRegistration) await repo.invalidateTarget(delivery, event.ownerId, target);
    }
    // Do not classify persistence failures as Firebase failures or retry accepted sends.
    await repo.finishDelivery(delivery, result);
  }

  async function processPending(sightingId = null) {
    const deadline = now() + budgetMs;
    let completed = true;
    for (const id of await repo.recoverAbandoned(scope)) await repo.summarize(id);
    const pendingScope = sightingId === null ? scope : { ...scope, sightingId };
    for (const notification of await repo.pendingNotifications(25, pendingScope)) {
      if (stopped || now() >= deadline) break;
      if (!inScope(notification)) continue;
      try {
        const event = await repo.loadEvent(repo.pool, notification.sightingId);
        const reason = !inScope(event) ? 'FUERA_PRUEBA_FCM' : skipReason(event);
        if (reason || event.ownerId !== notification.ownerId) {
          await repo.skipNotification(notification.id, `OMITIDA_${reason || 'DESTINATARIO_CAMBIO'}`);
          continue;
        }
        const unique = new Map();
        for (const target of await repo.listTargets(event.ownerId)) {
          if (typeof target.registrationId !== 'string' || !target.registrationId.trim()) continue;
          const fingerprint = createHash('sha256').update(target.registrationId).digest('hex');
          if (!unique.has(fingerprint)) unique.set(fingerprint, {
            sessionId: target.id, pushRegistrationId: target.pushRegistrationId, fingerprint });
        }
        if (!unique.size) {
          await repo.skipNotification(notification.id, 'SIN_DISPOSITIVOS');
          continue;
        }
        await repo.planDeliveries(notification.id, [...unique.values()]);
        for (let count = 0; count < 100 && !stopped && now() < deadline; count++) {
          const delivery = await repo.claimDelivery(notification.id, scope);
          if (!delivery) break;
          await deliver(notification, delivery);
        }
        await repo.summarize(notification.id);
      } catch (_) { completed = false; warn('PUSH_PROCESSING_FAILED', notification.id); }
    }
    return { enabled: true, completed };
  }

  function drain(sightingId = null) {
    if (!active || stopped) return Promise.resolve({ enabled: false, completed: true });
    if (inFlight) {
      return sightingId === null ? inFlight : inFlight.then(() => drain(sightingId));
    }
    inFlight = processPending(sightingId).catch(() => {
      warn('PUSH_RECOVERY_FAILED'); return { enabled: true, completed: false };
    })
      .finally(() => { inFlight = null; });
    return inFlight;
  }

  function wake(sightingId) {
    if (!active || stopped || processingMode !== 'inline') {
      return Promise.resolve({ enabled: false, completed: true });
    }
    // Target this sighting and let its HTTP request await all provider work.
    return drain(sightingId);
  }

  function start() {
    if (!active || timer || processingMode !== 'inline') return;
    stopped = false;
    void drain().catch(() => undefined);
    timer = setInterval(wake, 30000);
    timer.unref();
  }

  function stop() { stopped = true; clearInterval(timer); timer = null; }
  return { recordIntent, drain, wake, start, stop };
}

module.exports = { createNotificationsService,
  notificationsService: createNotificationsService() };
