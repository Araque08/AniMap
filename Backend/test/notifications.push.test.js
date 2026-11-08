const test = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { createNotificationsService } = require('../src/modules/notifications/notifications.service');

const NOW = Date.parse('2026-11-01T12:00:00Z');
function fixture(overrides = {}) {
  return {
    sightingId: 41, reportId: 8, authorId: 7, ownerId: 28,
    reportState: 'ACTIVO', petState: 'PERDIDA', ownerActive: true,
    ownerVerified: true, notificationsEnabled: true, species: 'Perro',
    speciesFilter: null, eventFilter: null, onlyMyZone: false, radiusKm: 2,
    lostLat: 4.65, lostLng: -74.11, lat: 4.651, lng: -74.11,
    date: '2026-11-01T11:59:00.000Z', ...overrides,
  };
}

const testScope = { testMode: true, testOwnerId: '28', testReportId: '8' };

test('wake inline procesa el avistamiento solicitado antes de resolver', async () => {
  const h = harness();
  await h.service.recordIntent({}, 41);
  const result = await h.service.wake(41);
  assert.deepEqual(result, { enabled: true, completed: true });
  assert.equal(h.calls.length, 1);
  assert.equal(h.notifications[0].state, 'ACEPTADA_FCM');
});

test('modo QA: solo el par destinatario/reporte autorizado registra y envia', async () => {
  const h = harness(testScope);
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.notifications.length, 1); assert.equal(h.calls.length, 1);
});

for (const changes of [{ ownerId: 29 }, { reportId: 9 }, { ownerId: 29, reportId: 9 }]) {
  test(`modo QA: evento ajeno ${JSON.stringify(changes)} no deja intencion futura`, async () => {
    const h = harness({ ...testScope, event: fixture(changes) });
    assert.equal(await h.service.recordIntent({}, 41), null);
    await h.service.drain(); await h.restart().drain();
    assert.equal(h.notifications.length, 0); assert.equal(h.deliveries.length, 0);
    assert.equal(h.calls.length, 0);
  });
}

for (const config of [
  { testOwnerId: undefined }, { testReportId: undefined },
  { testOwnerId: '' }, { testReportId: '0' }, { testOwnerId: '-1' },
  { testOwnerId: '28.5' }, { testReportId: '2147483648' },
  { testReportId: '8extra' }, { testMode: 'invalid' },
]) test(`modo QA incompleto o invalido bloquea toda actividad: ${JSON.stringify(config)}`, async () => {
  const h = harness({ ...testScope, ...config });
  for (const name of Object.keys(h.repo)) if (typeof h.repo[name] === 'function') {
    h.repo[name] = async () => assert.fail(`No debe acceder al repositorio: ${name}`);
  }
  assert.equal(await h.service.recordIntent({}, 41), null);
  h.service.start(); h.service.wake(); await h.service.drain();
  await new Promise(resolve => setImmediate(resolve)); h.service.stop();
  assert.equal(h.warnings.length, 0); assert.equal(h.calls.length, 0);
});

test('modo QA no sustituye el interruptor general deshabilitado', async () => {
  const h = harness({ ...testScope, enabled: false });
  await h.service.recordIntent({}, 41); await h.restart().drain();
  assert.equal(h.notifications.length, 0); assert.equal(h.calls.length, 0);
});

test('modo normal conserva eventos ajenos al par QA aunque haya IDs configurados', async () => {
  const h = harness({ ...testScope, testMode: false, event: fixture({ ownerId: 29, reportId: 9 }) });
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.notifications.length, 1); assert.equal(h.calls.length, 1);
});

test('modo QA: eventos concurrentes no se mezclan ni quedan para otro reinicio', async () => {
  const h = harness(testScope);
  const events = [fixture(), fixture({ sightingId: 42, ownerId: 29 }),
    fixture({ sightingId: 43, reportId: 9 })];
  h.repo.loadEvent = async (_, id) => { await Promise.resolve(); return events.find(e => e.sightingId === id); };
  await Promise.all(events.map(e => h.service.recordIntent({}, e.sightingId)));
  await Promise.all([h.service.drain(), h.service.drain()]); await h.restart().drain();
  assert.deepEqual(h.notifications.map(n => n.sightingId), [41]);
  assert.equal(h.calls.length, 1); assert.equal(h.calls[0].data.sightingId, '41');
});

test('modo QA: reinicio no reclama ni reconcilia pendientes y abandonadas ajenas', async () => {
  const h = harness(testScope);
  h.notifications.push({ id: 9, sightingId: 99, ownerId: 29, reportId: 8, state: 'PENDIENTE' },
    { id: 10, sightingId: 100, ownerId: 28, reportId: 9, state: 'PARCIAL' });
  h.deliveries.push({ id: 1, notificationId: 9, state: 'EN_PROCESO', startedAt: NOW - 900001 },
    { id: 2, notificationId: 10, state: 'REINTENTO', nextAt: NOW, attempts: 1 });
  const original = structuredClone({ notifications: h.notifications, deliveries: h.deliveries });
  await h.restart().drain();
  assert.deepEqual({ notifications: h.notifications, deliveries: h.deliveries }, original);
  assert.equal(h.calls.length, 0);
});

test('modo QA: dos procesadores tras reinicio recuperan solo el evento autorizado', async () => {
  const h = harness(testScope);
  await h.service.recordIntent({}, 41);
  h.notifications.push({ id: 9, sightingId: 99, ownerId: 29, reportId: 8, state: 'PENDIENTE' });
  h.deliveries.push({ id: 9, notificationId: 9, state: 'EN_PROCESO', startedAt: NOW - 900001 });
  const foreign = structuredClone({ notification: h.notifications[1], delivery: h.deliveries[0] });
  await Promise.all([h.restart().drain(), h.restart().drain()]);
  assert.deepEqual({ notification: h.notifications[1], delivery: h.deliveries[0] }, foreign);
  assert.equal(h.calls.length, 1); assert.equal(h.calls[0].data.sightingId, '41');
  assert.equal(h.notifications[0].state, 'ACEPTADA_FCM');
});

test('modo QA mantiene los filtros y vuelve a comprobarlos al recuperar', async () => {
  const h = harness({ ...testScope, event: fixture({ speciesFilter: 'Gato' }) });
  await h.service.recordIntent({}, 41); await h.restart().drain();
  assert.equal(h.notifications[0].state, 'OMITIDA_FILTRO_ESPECIE');
  assert.equal(h.calls.length, 0);
  const pending = harness(testScope); await pending.service.recordIntent({}, 41);
  pending.event.notificationsEnabled = false; await pending.restart().drain();
  assert.equal(pending.notifications[0].state, 'OMITIDA_NOTIFICACIONES_DESACTIVADAS');
  assert.equal(pending.calls.length, 0);
});

test('modo QA: cola inesperada ajena no llega a planificar entregas', async () => {
  const h = harness(testScope);
  h.repo.pendingNotifications = async () => [{ id: 99, sightingId: 41, ownerId: 29, reportId: 8 }];
  h.repo.planDeliveries = async () => assert.fail('No debe planificar una notificacion ajena');
  h.repo.skipNotification = async () => assert.fail('No debe modificar una notificacion ajena');
  await h.service.drain();
  assert.equal(h.warnings.length, 0); assert.equal(h.calls.length, 0);
});

test('modo QA: revalida el reporte del evento antes de cada envio', async () => {
  const h = harness(testScope); const plan = h.repo.planDeliveries;
  h.repo.planDeliveries = async (...args) => { await plan(...args); h.event.reportId = 9; };
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.calls.length, 0); assert.equal(h.deliveries[0].state, 'OMITIDA');
});

// Only the PG boundary and Firebase transport are simulated. Policy, payload,
// retry decisions, fingerprinting and the worker are the production service.
function harness({ event = fixture(), targets, send, enabled = true, ...testConfig } = {}) {
  let now = NOW;
  const notifications = [];
  const deliveries = [];
  const calls = [];
  const warnings = [];
  const devices = targets ?? [{ id: 215, registrationId: 'fixture-fid-A',
    updatedAt: '2026-11-01T11:50:00Z', usable: true }];
  const repo = {
    pool: {},
    async loadEvent() { return event; },
    async insertIntent(client, value, reason) {
      if (notifications.some(n => n.sightingId === value.sightingId)) return null;
      const row = { id: notifications.length + 1, sightingId: value.sightingId,
        ownerId: value.ownerId, reportId: value.reportId,
        state: reason ? `OMITIDA_${reason}` : 'PENDIENTE' };
      notifications.push(row);
      return row.id;
    },
    async recoverAbandoned(scope) {
      const ids = [];
      const scoped = n => !scope || (n.ownerId === scope.ownerId && n.reportId === scope.reportId);
      for (const d of deliveries) if (scoped(notifications.find(n => n.id === d.notificationId))
        && d.state === 'EN_PROCESO' && d.startedAt < now - 900000) {
        d.state = 'INDETERMINADA'; ids.push(d.notificationId);
      }
      for (const n of notifications) {
        const children = deliveries.filter(d => d.notificationId === n.id);
        if (scoped(n) && ['PENDIENTE', 'PARCIAL'].includes(n.state) && children.length
          && children.every(d => !['PENDIENTE', 'REINTENTO', 'EN_PROCESO'].includes(d.state))) ids.push(n.id);
      }
      return ids;
    },
    async pendingNotifications(limit, scope) {
      return notifications.filter(n => {
        const children = deliveries.filter(d => d.notificationId === n.id);
        return (!scope || ((scope.ownerId == null || n.ownerId === scope.ownerId)
          && (scope.reportId == null || n.reportId === scope.reportId)))
          && (scope?.sightingId == null || n.sightingId === scope.sightingId)
          && ((!children.length && ['PENDIENTE', 'PARCIAL'].includes(n.state))
          || children.some(d => ['PENDIENTE', 'REINTENTO'].includes(d.state) && d.nextAt <= now));
      });
    },
    async listTargets() { return devices.filter(d => d.usable); },
    async planDeliveries(notificationId, values) {
      for (const v of values) {
        const existing = deliveries.find(d => d.notificationId === notificationId && d.fingerprint === v.fingerprint);
        if (!existing) deliveries.push({ id: deliveries.length + 1, notificationId,
          ...v, state: 'PENDIENTE', attempts: 0, nextAt: NOW });
        else if (['PENDIENTE', 'REINTENTO'].includes(existing.state)) existing.sessionId = v.sessionId;
      }
    },
    async claimDelivery(notificationId) {
      const d = deliveries.find(d => d.notificationId === notificationId && ['PENDIENTE', 'REINTENTO'].includes(d.state)
        && d.nextAt <= now && d.attempts < 3);
      if (!d) return null;
      d.state = 'EN_PROCESO'; d.attempts++; d.startedAt = now;
      return { ...d };
    },
    async currentTarget(delivery) {
      const d = devices.find(t => t.id === delivery.sessionId && t.usable);
      if (!d || createHash('sha256').update(d.registrationId).digest('hex') !== delivery.fingerprint) return null;
      return { ...d };
    },
    async finishDelivery(delivery, result) {
      Object.assign(deliveries.find(d => d.id === delivery.id), result,
        { nextAt: result.nextAt ? Date.parse(result.nextAt) : null });
    },
    async invalidateTarget(delivery, ownerId, original) {
      const d = devices.find(t => t.id === delivery.sessionId);
      if (d?.registrationId === original.registrationId && d.updatedAt === original.updatedAt) d.usable = false;
    },
    async skipNotification(id, reason) {
      notifications.find(n => n.id === id).state = reason;
      for (const d of deliveries) if (d.notificationId === id && ['PENDIENTE', 'REINTENTO'].includes(d.state)) d.state = 'OMITIDA';
    },
    async summarize(id) {
      const children = deliveries.filter(d => d.notificationId === id);
      const pending = children.some(d => ['PENDIENTE', 'REINTENTO', 'EN_PROCESO'].includes(d.state));
      const accepted = children.some(d => d.state === 'ACEPTADA_FCM');
      notifications.find(n => n.id === id).state = pending
        ? (accepted ? 'PARCIAL' : 'PENDIENTE')
        : accepted ? 'ACEPTADA_FCM' : 'FINALIZADA';
    },
  };
  const service = createNotificationsService({ repo, enabled, ...testConfig, now: () => now,
    random: () => 0, logger: { warn: (...args) => warnings.push(args) },
    sender: { async send(message) {
      calls.push(message);
      return send ? send(message, devices) : 'projects/animapbd/messages/mock-message';
    } },
  });
  return { service, repo, event, notifications, deliveries, devices, calls, warnings,
    advance(ms) { now += ms; }, restart() {
      return createNotificationsService({ repo, enabled, ...testConfig, now: () => now, random: () => 0,
        logger: { warn() {} }, sender: { async send(message) {
          calls.push(message); return 'projects/animapbd/messages/mock-after-restart';
        } } });
    } };
}

test('vinculado: persiste un evento, dirige FID al dueño y registra aceptación, no recepción', async () => {
  const h = harness();
  await h.service.recordIntent({}, 41);
  assert.equal(h.calls.length, 0);
  await h.service.drain();
  assert.equal(h.notifications[0].ownerId, 28);
  assert.equal(h.calls.length, 1);
  assert.equal(h.calls[0].fid, 'fixture-fid-A');
  assert.deepEqual(h.calls[0].data, { type: 'AVISTAMIENTO_VINCULADO',
    notificationId: '1', sightingId: '41', reportId: '8', ownerId: '28' });
  assert.equal(h.deliveries[0].state, 'ACEPTADA_FCM');
  assert.ok(h.deliveries[0].acceptedAt);
  assert.equal(h.deliveries[0].receivedAt, undefined);
  assert.ok(!JSON.stringify(h.deliveries).includes('fixture-fid-A'));
  assert.ok(!JSON.stringify(h.calls[0]).includes('authorId'));
});

test('independiente no genera intención', async () => {
  const h = harness({ event: fixture({ reportId: null }) });
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.notifications.length, 0); assert.equal(h.calls.length, 0);
});

test('autor propietario no genera intención', async () => {
  const h = harness({ event: fixture({ authorId: 28 }) });
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.notifications.length, 0); assert.equal(h.calls.length, 0);
});

for (const [name, changes, reason] of [
  ['reporte inactivo', { reportState: 'FINALIZADO' }, 'REPORTE_INACTIVO'],
  ['cuenta no disponible', { ownerActive: false }, 'CUENTA_NO_DISPONIBLE'],
  ['notificaciones desactivadas', { notificationsEnabled: false }, 'NOTIFICACIONES_DESACTIVADAS'],
  ['especie distinta', { speciesFilter: 'Gato' }, 'FILTRO_ESPECIE'],
  ['tipo distinto', { eventFilter: 'PERDIDA' }, 'FILTRO_TIPO'],
  ['zona sin punto original', { onlyMyZone: true, lostLat: null }, 'ZONA_SIN_COORDENADAS'],
  ['zona sin punto avistado', { onlyMyZone: true, lng: '' }, 'ZONA_SIN_COORDENADAS'],
  ['radio inválido', { onlyMyZone: true, radiusKm: null }, 'ZONA_RADIO_INVALIDO'],
  ['fuera del radio', { onlyMyZone: true, radiusKm: 1, lat: 4.67 }, 'FUERA_RADIO'],
]) test(`${name}: registra motivo y no envía`, async () => {
  const h = harness({ event: fixture(changes) });
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.calls.length, 0);
  assert.equal(h.notifications[0].state, `OMITIDA_${reason}`);
});

test('especie/tipo permitidos y radio alrededor del reporte permiten enviar', async () => {
  const h = harness({ event: fixture({ onlyMyZone: true, radiusKm: 1,
    speciesFilter: 'perro', eventFilter: 'AVISTAMIENTO' }) });
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.calls.length, 1);
});

test('sin dispositivos no envía ni entra en reintentos indefinidos', async () => {
  const h = harness({ targets: [] });
  await h.service.recordIntent({}, 41); await h.service.drain(); await h.service.drain();
  assert.equal(h.calls.length, 0); assert.equal(h.notifications[0].state, 'SIN_DISPOSITIVOS');
});

test('revalida revocación o vencimiento justo antes del envío', async () => {
  const h = harness();
  const plan = h.repo.planDeliveries;
  h.repo.planDeliveries = async (...args) => { await plan(...args); h.devices[0].usable = false; };
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.calls.length, 0); assert.equal(h.deliveries[0].state, 'OMITIDA');
});

test('revalida preferencia y estado del reporte al procesar intención pendiente', async () => {
  const h = harness(); await h.service.recordIntent({}, 41);
  h.event.reportState = 'FINALIZADO'; await h.service.drain();
  assert.equal(h.calls.length, 0);
  assert.equal(h.notifications[0].state, 'OMITIDA_REPORTE_INACTIVO');
});

test('error transitorio usa espera exponencial y no supera tres intentos', async () => {
  const h = harness({ send() { throw Object.assign(new Error('mock'), { code: 'messaging/server-unavailable' }); } });
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.deliveries[0].state, 'REINTENTO');
  assert.equal(h.deliveries[0].nextAt, NOW + 60000);
  await h.service.drain(); assert.equal(h.calls.length, 1);
  h.advance(60000); await h.service.drain();
  assert.equal(h.deliveries[0].nextAt, NOW + 180000);
  h.advance(120000); await h.service.drain();
  assert.equal(h.deliveries[0].state, 'FALLIDA_PERMANENTE');
  h.advance(9999999); await h.service.drain(); assert.equal(h.calls.length, 3);
});

test('un error permanente invalida solo el registro que falló y no se reintenta', async () => {
  const h = harness({ send() { throw Object.assign(new Error('mock'), { code: 'messaging/registration-token-not-registered' }); } });
  await h.service.recordIntent({}, 41); await h.service.drain(); await h.service.drain();
  assert.equal(h.devices[0].usable, false); assert.equal(h.calls.length, 1);
  assert.equal(h.deliveries[0].state, 'FALLIDA_PERMANENTE');
});

test('respuesta tardía de un identificador antiguo no borra su reemplazo', async () => {
  const h = harness({ send(message, devices) {
    devices[0].registrationId = 'fixture-fid-new'; devices[0].updatedAt = '2026-11-01T12:01:00Z';
    throw Object.assign(new Error('mock'), { code: 'messaging/registration-token-not-registered' });
  } });
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.devices[0].usable, true);
  assert.equal(h.devices[0].registrationId, 'fixture-fid-new');
});

test('eventos duplicados y ejecuciones concurrentes no repiten entrega aceptada', async () => {
  const h = harness();
  await h.service.recordIntent({}, 41); await h.service.recordIntent({}, 41);
  await Promise.all([h.service.drain(), h.service.drain()]); await h.service.drain();
  assert.equal(h.notifications.length, 1); assert.equal(h.deliveries.length, 1);
  assert.equal(h.calls.length, 1);
});

test('deduplica identificadores repetidos sin persistirlos en claro', async () => {
  const h = harness({ targets: [
    { id: 215, registrationId: 'fixture-fid-A', usable: true },
    { id: 216, registrationId: 'fixture-fid-A', usable: true },
  ] });
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.calls.length, 1); assert.equal(h.deliveries.length, 1);
  assert.equal(h.deliveries[0].fingerprint.length, 64);
});

test('reinicio recupera una intención confirmada antes de despacharla', async () => {
  const h = harness(); await h.service.recordIntent({}, 41);
  await h.restart().drain();
  assert.equal(h.calls.length, 1); assert.equal(h.deliveries[0].state, 'ACEPTADA_FCM');
});

test('reinicio conserva el plazo del reintento y no repite dispositivos ya aceptados', async () => {
  const h = harness({ targets: [
    { id: 215, registrationId: 'fixture-fid-A', usable: true },
    { id: 216, registrationId: 'fixture-fid-B', usable: true },
  ], send(message) { if (message.fid === 'fixture-fid-B') throw Object.assign(new Error('mock'), { code: 'messaging/server-unavailable' }); return 'projects/animapbd/messages/mock'; } });
  await h.service.recordIntent({}, 41); await h.service.drain();
  await h.restart().drain(); assert.equal(h.calls.length, 2);
  h.advance(60000); await h.restart().drain();
  assert.equal(h.calls.filter(c => c.fid === 'fixture-fid-A').length, 1);
  assert.equal(h.calls.filter(c => c.fid === 'fixture-fid-B').length, 2);
});

test('un envío interrumpido se conserva como indeterminado y no se reenvía automáticamente', async () => {
  const h = harness(); await h.service.recordIntent({}, 41);
  await h.repo.planDeliveries(1, [{ sessionId: 215, fingerprint: createHash('sha256').update('fixture-fid-A').digest('hex') }]);
  await h.repo.claimDelivery(1); h.advance(900001); await h.restart().drain();
  assert.equal(h.deliveries[0].state, 'INDETERMINADA'); assert.equal(h.calls.length, 0);
});

test('deshabilitado por defecto no persiste ni consulta ni inicia Firebase', async () => {
  const h = harness({ enabled: false });
  h.repo.loadEvent = async () => assert.fail('PG must not be used');
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.notifications.length, 0); assert.equal(h.calls.length, 0);
});

test('errores desconocidos no filtran identificadores ni mensajes del proveedor', async () => {
  const h = harness({ send() { throw Object.assign(new Error('fixture-fid-A confidential'), { code: 'fixture-fid-A' }); } });
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.ok(!JSON.stringify(h.deliveries).includes('confidential'));
  assert.ok(!JSON.stringify(h.warnings).includes('fixture-fid-A'));
  assert.equal(h.calls.length, 1);
});

test('renovar el mismo FID después del intento protege la nueva versión de la asociación', async () => {
  const h = harness({ send(message, devices) {
    devices[0].updatedAt = '2026-11-01T12:02:00Z';
    throw Object.assign(new Error('mock'), { code: 'messaging/installation-id-not-registered' });
  } });
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.devices[0].usable, true);
  assert.equal(h.deliveries[0].state, 'FALLIDA_PERMANENTE');
});

test('una asociación cambiada mientras espera no recibe el mensaje con credenciales antiguas', async () => {
  const h = harness(); const plan = h.repo.planDeliveries;
  h.repo.planDeliveries = async (...args) => {
    await plan(...args); h.devices[0].registrationId = 'fixture-fid-replacement';
  };
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.calls.length, 0);
  assert.equal(h.deliveries[0].state, 'OMITIDA');
});

test('Retry-After mayor que el backoff aplaza el siguiente intento', async () => {
  const h = harness({ send() { throw Object.assign(new Error('mock'), {
    code: 'messaging/server-unavailable', retryAfterMs: 300000,
  }); } });
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.deliveries[0].nextAt, NOW + 300000);
  h.advance(299999); await h.service.drain(); assert.equal(h.calls.length, 1);
});

test('la aceptación remota seguida de fallo PG no provoca un segundo envío', async () => {
  const h = harness();
  h.repo.finishDelivery = async () => { throw new Error('mock PG write failure'); };
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.calls.length, 1); assert.equal(h.deliveries[0].state, 'EN_PROCESO');
  h.advance(900001); await h.restart().drain();
  assert.equal(h.calls.length, 1); assert.equal(h.deliveries[0].state, 'INDETERMINADA');
});

test('radio cero incluye el punto original exacto; sin filtro no impone una ubicación del usuario', async () => {
  const h = harness({ event: fixture({ onlyMyZone: true, radiusKm: 0, lat: 4.65, lng: -74.11 }) });
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.calls.length, 1);
  const unrestricted = harness({ event: fixture({ lostLat: null, lostLng: null }) });
  await unrestricted.service.recordIntent({}, 41); await unrestricted.service.drain();
  assert.equal(unrestricted.calls.length, 1);
});

test('reinicio reconcilia el resumen tras guardar aceptación sin repetir Firebase', async () => {
  const h = harness(); const summarize = h.repo.summarize;
  h.repo.summarize = async () => { throw new Error('mock interruption before summary'); };
  await h.service.recordIntent({}, 41); await h.service.drain();
  assert.equal(h.notifications[0].state, 'PENDIENTE');
  assert.equal(h.deliveries[0].state, 'ACEPTADA_FCM');
  h.repo.summarize = summarize; await h.restart().drain();
  assert.equal(h.notifications[0].state, 'ACEPTADA_FCM'); assert.equal(h.calls.length, 1);
});

test('un hijo pendiente bajo un resumen terminal se procesa sin repetir los aceptados', async () => {
  const h = harness(); await h.service.recordIntent({}, 41); await h.service.drain();
  h.devices.push({ id: 216, registrationId: 'fixture-fid-B', usable: true });
  await h.repo.planDeliveries(1, [{ sessionId: 216,
    fingerprint: createHash('sha256').update('fixture-fid-B').digest('hex') }]);
  assert.equal(h.notifications[0].state, 'ACEPTADA_FCM');
  await h.restart().drain();
  assert.equal(h.calls.filter(c => c.fid === 'fixture-fid-A').length, 1);
  assert.equal(h.calls.filter(c => c.fid === 'fixture-fid-B').length, 1);
  assert.equal(h.notifications[0].state, 'ACEPTADA_FCM');
});
