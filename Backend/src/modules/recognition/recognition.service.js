const { createHash } = require('node:crypto');
const { recognitionWorker, failure } = require('./recognition.worker');
const { createRecognitionRepository } = require('./recognition.repository');
const hash = content => createHash('sha256').update(content).digest('hex');
const key = photo => `${photo.reportId}:${photo.petId}:${photo.photoId}`;

function createRecognitionService({ repo = createRecognitionRepository(), worker = recognitionWorker,
  threshold = process.env.RECOGNITION_SIMILARITY_THRESHOLD === undefined ? 0.80
    : (process.env.RECOGNITION_SIMILARITY_THRESHOLD.trim() ? Number(process.env.RECOGNITION_SIMILARITY_THRESHOLD) : NaN),
  topK = 5, timeoutMs = 120000 } = {}) {
  let busy = false;
  async function search(content, { signal } = {}) {
    if (busy) throw failure('RECOGNITION_BUSY');
    if (!Number.isFinite(threshold) || threshold < 0 || threshold > 1) throw failure('RECOGNITION_UNAVAILABLE');
    busy = true;
    const controller = new AbortController(), abort = () => controller.abort();
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) controller.abort();
    let queryId, rejectDeadline, completed = false;
    const deadline = new Promise((_, reject) => { rejectDeadline = reject; });
    const onAbort = () => { rejectDeadline(failure('RECOGNITION_TIMEOUT')); worker.close(); };
    controller.signal.addEventListener('abort', onAbort, { once: true });
    const timer = setTimeout(abort, timeoutMs);
    const check = () => { if (controller.signal.aborted) throw failure('RECOGNITION_TIMEOUT'); };
    const request = (action, payload) => { check(); return worker.request(action, payload, { signal: controller.signal }); };
    try {
      const result = await Promise.race([deadline, (async () => {
        queryId = (await request('query', { image: content.toString('base64') })).queryId;
        if (typeof queryId !== 'string' || !queryId) throw failure('RECOGNITION_UNAVAILABLE');
        const photos = await repo.activePhotos(), scored = [];
        let skippedImages = 0, searchedImages = 0;
        for (const photo of photos) {
          check(); const bytes = await repo.photoBytes(photo); check();
          if (!bytes?.length || bytes.length > 5 * 1024 * 1024) { skippedImages++; continue; }
          let result;
          try { result = await request('compare', { queryId, image: bytes.toString('base64') }); }
          catch (error) {
            if (error.code === 'INVALID_RECOGNITION_IMAGE') { skippedImages++; continue; }
            throw error;
          }
          if (!Number.isFinite(result.similarity) || Math.abs(result.similarity) > 1) throw failure('RECOGNITION_UNAVAILABLE');
          searchedImages++;
          if (result.similarity >= threshold) scored.push({ ...photo, similarity: result.similarity, hash: hash(bytes) });
        }
        const current = new Map((await repo.activePhotos()).map(photo => [key(photo), photo]));
        const matches = [], included = new Set();
        scored.sort((a, b) => b.similarity - a.similarity || a.reportId - b.reportId || a.photoId.localeCompare(b.photoId));
        for (const photo of scored) {
          check(); const fresh = current.get(key(photo));
          if (!fresh || included.has(photo.reportId)) continue;
          const bytes = await repo.photoBytes(fresh); check();
          if (!bytes || hash(bytes) !== photo.hash) continue;
          included.add(photo.reportId);
          matches.push({ reportId: fresh.reportId,
            pet: { id: fresh.petId, nombre: fresh.nombre, especie: fresh.especie, raza: fresh.raza, color: fresh.color },
            photo: { id: fresh.photoId, url: `/api/map/images/${fresh.photoId}` }, similarity: photo.similarity });
          if (matches.length >= topK) break;
        }
        return { model: 'resnet50-imagenet1k-v2', threshold, searchedImages, skippedImages, matches };
      })()]);
      completed = true;
      return result;
    } finally {
      clearTimeout(timer); signal?.removeEventListener('abort', abort);
      controller.signal.removeEventListener('abort', onAbort);
      if (!completed) worker.close();
      else if (queryId) {
        try { await worker.request('release', { queryId }, { timeoutMs: 2000 }); } catch (_) { worker.close(); }
      }
      busy = false;
    }
  }
  return { search };
}
module.exports = { createRecognitionService, recognitionService: createRecognitionService() };
