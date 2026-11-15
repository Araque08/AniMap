const env = require('../../config/env');
const { createMatchRepository } = require('./recognition.matches.repository');
const { recognitionService } = require('./recognition.service');
const { notificationsService, skipReason } = require('../notifications/notifications.service');

const MAX_OWNERS = 3;
const httpError = (message, statusCode) => Object.assign(new Error(message), { statusCode });

function createMatchService({ repo = createMatchRepository(), recognizer = recognitionService,
  notifications = notificationsService, enabled = env.PHOTO_MATCH_ENABLED,
  processingMode = env.FCM_PROCESSING_MODE, logger = console, now = Date.now,
  budgetMs = 45000 } = {}) {
  let inFlight = null, timer = null, stopped = false;
  const warn = code => logger.warn('AniMap reconocimiento publicado', { code });

  async function finish(job, result) {
    await repo.transaction(async client => {
      if (!await repo.isCurrent(client, job)) return;
      const owners = new Set();
      const ranked = result.matches.filter(m => Number.isFinite(m.similarity)
        && m.similarity >= result.threshold && m.similarity <= 1)
        .sort((a, b) => b.similarity - a.similarity || a.reportId - b.reportId);
      for (const match of ranked) {
        if (owners.size >= MAX_OWNERS) break;
        const event = await repo.candidate(client, job.sightingId, match.reportId, match.photo.id);
        if (!event || skipReason(event) || !notifications.allowsEvent(event) || owners.has(event.ownerId)) continue;
        const notificationId = await notifications.recordMatchIntent(client, event, { similarity: match.similarity });
        if (notificationId === null) continue;
        await repo.saveMatch(client, event, { similarity: match.similarity,
          threshold: result.threshold, model: result.model, notificationId });
        owners.add(event.ownerId);
      }
      // The existing unique (sighting, recipient) index coalesces a linked
      // sighting alert with its photographic match for the same owner.
      await notifications.recordIntent(client, job.sightingId);
      await repo.complete(client, job);
    });
  }

  async function failed(job, code, permanent) {
    await repo.transaction(async client => {
      if (!await repo.isCurrent(client, job)) return;
      if (await repo.fail(client, job, code, { permanent })) {
        await notifications.recordIntent(client, job.sightingId);
      }
    });
  }

  async function processPending() {
    const deadline = now() + budgetMs;
    let completed = true;
    for (let count = 0; count < 3 && !stopped && now() < deadline; count++) {
      const job = await repo.claim();
      if (!job) break;
      if (job.exhausted) {
        await failed(job, 'MATCH_ANALYSIS_EXHAUSTED', true);
        await notifications.wake(job.sightingId).catch(() => warn('MATCH_DELIVERY_DEFERRED'));
        continue;
      }
      let result;
      try {
        const photo = await repo.photo(job);
        if (!photo?.length) throw Object.assign(new Error(), { code: 'MATCH_PHOTO_UNAVAILABLE' });
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), Math.max(1, deadline - now()));
        try { result = await recognizer.search(photo, { signal: controller.signal, allMatches: true }); }
        finally { clearTimeout(timeout); }
        if (result.model !== 'resnet50-imagenet1k-v2' || !Number.isFinite(result.threshold)
          || result.threshold < 0 || result.threshold > 1 || !Array.isArray(result.matches)) {
          throw Object.assign(new Error(), { code: 'RECOGNITION_UNAVAILABLE' });
        }
      } catch (error) {
        const allowed = ['RECOGNITION_BUSY', 'RECOGNITION_TIMEOUT', 'INVALID_RECOGNITION_IMAGE', 'MATCH_PHOTO_UNAVAILABLE'];
        const code = allowed.includes(error.code) ? error.code : 'RECOGNITION_UNAVAILABLE';
        await failed(job, code, ['INVALID_RECOGNITION_IMAGE', 'MATCH_PHOTO_UNAVAILABLE'].includes(code));
        completed = false;
        await notifications.wake(job.sightingId).catch(() => warn('MATCH_DELIVERY_DEFERRED'));
        continue;
      }
      // Persistence failures leave the claim recoverable; they are not model failures.
      await finish(job, result);
      await notifications.wake(job.sightingId).catch(() => warn('MATCH_DELIVERY_DEFERRED'));
    }
    return { enabled: true, completed };
  }

  function drain() {
    if (!enabled || stopped) return Promise.resolve({ enabled: false, completed: true });
    if (inFlight) return inFlight;
    inFlight = processPending().catch(() => {
      warn('MATCH_PROCESSING_DEFERRED'); return { enabled: true, completed: false };
    }).finally(() => { inFlight = null; });
    return inFlight;
  }
  function wake() {
    return processingMode === 'inline' ? drain() : Promise.resolve({ enabled: false, completed: true });
  }
  function start() {
    if (!enabled || timer || processingMode !== 'inline') return;
    stopped = false;
    void drain();
    timer = setInterval(() => { void drain(); }, 30000);
    timer.unref();
  }
  function stop() { stopped = true; clearInterval(timer); timer = null; }
  function requireEnabled() {
    if (!enabled) throw httpError('El historial de coincidencias todavía no está habilitado.', 503);
  }
  async function list(ownerId, before) { requireEnabled(); return repo.list(ownerId, before); }
  async function detail(ownerId, id) {
    requireEnabled(); const result = await repo.detail(ownerId, id);
    if (!result) throw httpError('Coincidencia no encontrada', 404);
    return result;
  }
  async function image(ownerId, id) {
    requireEnabled(); const result = await repo.image(ownerId, id);
    if (!result) throw httpError('Fotografía no encontrada', 404);
    return result;
  }
  return { enabled, enqueue: repo.enqueue, findRequest: repo.findRequest,
    list, detail, image, drain, wake, start, stop };
}

module.exports = { createMatchService, matchService: createMatchService() };
