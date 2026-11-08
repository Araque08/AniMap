const { OAuth2Client } = require('google-auth-library');
const env = require('../../config/env');
const { notificationsService } = require('./notifications.service');

const oidc = new OAuth2Client();
async function verifyGoogleToken(idToken, audience) {
  const ticket = await oidc.verifyIdToken({ idToken, audience });
  return ticket.getPayload();
}

// The mobile API is public at Cloud Run's edge. Protect this route separately;
// an AniMap access token is not sufficient to invoke the worker.
function createWorkerHandler({ service = notificationsService,
  audience = env.NOTIFICATION_WORKER_AUDIENCE,
  serviceAccount = env.NOTIFICATION_WORKER_SERVICE_ACCOUNT_EMAIL,
  verify = verifyGoogleToken } = {}) {
  return async (req, res) => {
    if (!audience?.startsWith('https://') || !serviceAccount?.endsWith('.iam.gserviceaccount.com')) {
      return res.status(503).json({ ok: false, code: 'WORKER_NOT_CONFIGURED' });
    }
    const match = /^Bearer ([^\s]+)$/.exec(req.get('authorization') || '');
    if (!match) return res.status(401).json({ ok: false, code: 'WORKER_AUTH_REQUIRED' });
    let identity;
    try { identity = await verify(match[1], audience); }
    catch (_) { return res.status(401).json({ ok: false, code: 'WORKER_AUTH_INVALID' }); }
    if (identity?.email !== serviceAccount || identity.email_verified !== true) {
      return res.status(403).json({ ok: false, code: 'WORKER_FORBIDDEN' });
    }
    try {
      const result = await service.drain();
      return res.status(result.completed ? 200 : 503).json({ ok: result.completed, ...result });
    } catch (_) {
      return res.status(503).json({ ok: false, code: 'WORKER_UNAVAILABLE' });
    }
  };
}

module.exports = { createWorkerHandler };
