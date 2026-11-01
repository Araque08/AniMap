const test = require('node:test');
const assert = require('node:assert/strict');
const { createFirebaseSender, classifyFirebaseError } = require('../src/modules/notifications/firebase.sender');

test('SDK recibe fid y proyecto animapbd mediante ADC, sin Authentication ni Firestore', async () => {
  const configurations = [];
  const sent = [];
  const credential = {};
  const sender = createFirebaseSender({ enabled: true, loadSdk: () => ({
    app: { getApps: () => [], applicationDefault: () => credential,
      initializeApp: (options, name) => { configurations.push({ options, name }); return { options }; } },
    messaging: { getMessaging: () => ({ send: async message => {
      sent.push(message); return 'projects/animapbd/messages/mock';
    } }) },
  }) });
  const result = await sender.send({ fid: 'fixture-fid', notification: { title: 'Prueba', body: 'Prueba' },
    data: { sightingId: '41' }, tag: 'animap-notification-1' });
  assert.equal(result, 'projects/animapbd/messages/mock');
  assert.equal(configurations[0].options.projectId, 'animapbd');
  assert.equal(configurations[0].options.credential, credential);
  assert.equal(sent[0].fid, 'fixture-fid');
  assert.equal(sent[0].token, undefined);
  assert.equal(sent[0].android.notification.tag, 'animap-notification-1');
});

test('deshabilitado no carga SDK ni obtiene credenciales', async () => {
  const sender = createFirebaseSender({ enabled: false, loadSdk: () => assert.fail('SDK must not load') });
  await assert.rejects(sender.send({ fid: 'fixture-fid' }), e => e.code === 'PUSH_DISABLED');
});

test('fallo de ADC se devuelve saneado, sin mensaje o credenciales del proveedor', async () => {
  const sender = createFirebaseSender({ enabled: true, loadSdk: () => {
    throw new Error('credential-secret fixture-fid');
  } });
  await assert.rejects(sender.send({ fid: 'fixture-fid' }), e =>
    e.code === 'PUSH_CONFIGURATION_UNAVAILABLE' && !e.message.includes('secret') && !e.cause);
});

test('respeta Retry-After y no confunde error de payload con identificador inválido', () => {
  const retry = classifyFirebaseError({ code: 'messaging/server-unavailable',
    httpResponse: { headers: { 'retry-after': '120' } } }, 0);
  assert.equal(retry.transient, true); assert.equal(retry.retryAfterMs, 120000);
  const badPayload = classifyFirebaseError({ code: 'messaging/invalid-argument' });
  assert.equal(badPayload.invalidRegistration, false);
  assert.equal(badPayload.transient, false);
});

test('errores no reconocidos no propagan valores arbitrarios ni se reintentan', () => {
  const result = classifyFirebaseError({ code: 'fixture-fid-secret', message: 'secret' });
  assert.equal(result.code, 'FCM_UNKNOWN');
  assert.equal(result.indeterminate, true);
  assert.ok(!JSON.stringify(result).includes('secret'));
});

test('el código real del SDK para un FID no registrado es permanente y permite invalidarlo', () => {
  const result = classifyFirebaseError({ code: 'messaging/installation-id-not-registered' });
  assert.equal(result.invalidRegistration, true);
  assert.equal(result.transient, false);
});

test('el adaptador conserva Retry-After pero descarta la respuesta cruda del proveedor', async () => {
  const sender = createFirebaseSender({ enabled: true, loadSdk: () => ({
    app: { getApps: () => [], applicationDefault: () => ({}), initializeApp: () => ({}) },
    messaging: { getMessaging: () => ({ async send() {
      throw Object.assign(new Error('fixture-fid confidential'), {
        code: 'messaging/server-unavailable', httpResponse: { headers: { 'retry-after': '300' } },
      });
    } }) },
  }) });
  await assert.rejects(sender.send({ fid: 'fixture-fid' }), error => {
    assert.equal(classifyFirebaseError(error).retryAfterMs, 300000);
    assert.equal(error.httpResponse, undefined);
    assert.equal(error.cause, undefined);
    return !error.message.includes('fixture-fid');
  });
});

test('SDK instalado acepta fid; la credencial simulada impide toda solicitud externa', async t => {
  const appSdk = require('firebase-admin/app');
  const messagingSdk = require('firebase-admin/messaging');
  t.mock.method(require('node:https'), 'request', () => assert.fail('No outbound request allowed'));
  let credentialCalls = 0;
  const sender = createFirebaseSender({ enabled: true, loadSdk: () => ({
    app: { ...appSdk, applicationDefault: () => ({ async getAccessToken() {
      credentialCalls++;
      throw new Error('mock credentials unavailable');
    } }) }, messaging: messagingSdk,
  }) });
  t.after(async () => {
    const app = appSdk.getApps().find(value => value.name === 'animap-push');
    if (app) await appSdk.deleteApp(app);
  });
  await assert.rejects(sender.send({ fid: 'fixture-fid', notification: { title: 'Prueba' },
    data: { sightingId: '41' }, tag: 'animap-notification-1' }));
  assert.equal(credentialCalls, 1, 'El payload debe superar la validación FID del SDK');
});
