const env = require('../../config/env');

const TRANSIENT = new Set([
  'messaging/server-unavailable', 'messaging/internal-error',
  'messaging/quota-exceeded', 'messaging/message-rate-exceeded',
  'messaging/device-message-rate-exceeded', 'messaging/topics-message-rate-exceeded',
]);
const INVALID_REGISTRATION = new Set([
  'messaging/registration-token-not-registered', 'messaging/invalid-registration-token',
  'messaging/installation-id-not-registered',
]);
const INDETERMINATE = new Set([
  'FCM_RESULT_UNKNOWN', 'FCM_UNKNOWN', 'app/network-timeout',
  'app/network-error', 'messaging/unknown-error',
]);
const PERMANENT = new Set([
  'messaging/invalid-argument', 'messaging/invalid-payload',
  'messaging/payload-size-limit-exceeded', 'messaging/mismatched-credential',
  'messaging/authentication-error', 'messaging/invalid-apns-credentials',
  'app/invalid-credential', 'PUSH_CONFIGURATION_UNAVAILABLE', 'PUSH_DISABLED',
]);

function classifyFirebaseError(error, now = Date.now()) {
  const raw = error?.code;
  const known = TRANSIENT.has(raw) || INVALID_REGISTRATION.has(raw)
    || PERMANENT.has(raw) || INDETERMINATE.has(raw);
  const header = error?.httpResponse?.headers?.['retry-after'];
  let retryAfterMs = Number.isFinite(error?.retryAfterMs) && error.retryAfterMs > 0
    ? error.retryAfterMs : 0;
  if (typeof header === 'string' && header.length < 100) {
    const seconds = /^\d+$/.test(header) ? Number(header) : NaN;
    const delay = Number.isFinite(seconds) ? seconds * 1000 : Date.parse(header) - now;
    if (Number.isFinite(delay) && delay > 0) retryAfterMs = delay;
  }
  return {
    code: known ? raw : 'FCM_UNKNOWN',
    transient: TRANSIENT.has(raw),
    invalidRegistration: INVALID_REGISTRATION.has(raw),
    indeterminate: !known || INDETERMINATE.has(raw),
    retryAfterMs,
  };
}

function failure(code) {
  const error = new Error('Servicio push no disponible');
  error.code = code;
  return error;
}

function createFirebaseSender({ enabled = env.FCM_PUSH_ENABLED, loadSdk = () => ({
  app: require('firebase-admin/app'), messaging: require('firebase-admin/messaging'),
}) } = {}) {
  let messaging;
  function initialize() {
    if (messaging) return messaging;
    const sdk = loadSdk();
    const existing = sdk.app.getApps().find(app => app.name === 'animap-push');
    if (existing && existing.options.projectId !== 'animapbd') throw failure('PUSH_CONFIGURATION_UNAVAILABLE');
    const app = existing || sdk.app.initializeApp({
      credential: sdk.app.applicationDefault(), projectId: 'animapbd',
    }, 'animap-push');
    messaging = sdk.messaging.getMessaging(app);
    return messaging;
  }

  async function send({ fid, notification, data, tag }) {
    if (!enabled) throw failure('PUSH_DISABLED');
    let transport;
    try { transport = initialize(); } catch (_) { throw failure('PUSH_CONFIGURATION_UNAVAILABLE'); }
    let timer;
    try {
      const id = await Promise.race([
        transport.send({ fid, notification, data,
          android: { priority: 'high', notification: { tag } } }),
        new Promise((_, reject) => {
          // A timed-out request can still be accepted remotely. It is not retried
          // automatically: the worker records an indeterminate result.
          timer = setTimeout(() => reject(failure('FCM_RESULT_UNKNOWN')), 30000);
          timer.unref();
        }),
      ]);
      if (typeof id !== 'string' || !id.startsWith('projects/animapbd/messages/')) {
        throw failure('FCM_RESULT_UNKNOWN');
      }
      return id;
    } catch (error) {
      const result = classifyFirebaseError(error);
      const safe = failure(result.code);
      // Only the parsed delay is retained, never provider messages or headers.
      safe.retryAfterMs = result.retryAfterMs;
      throw safe;
    } finally { clearTimeout(timer); }
  }
  return { send };
}

module.exports = { createFirebaseSender, classifyFirebaseError };
