const express = require('express');
const multer = require('multer');
const { rateLimit } = require('express-rate-limit');
const auth = require('../../middleware/auth.middleware');
const { recognitionService } = require('./recognition.service');
const MAX_BYTES = 5 * 1024 * 1024;

function validImage(file) {
  if (!file?.buffer?.length) return false;
  const b = file.buffer, ext = file.originalname.split('.').pop().toLowerCase();
  return (['jpg', 'jpeg'].includes(ext) && file.mimetype === 'image/jpeg' && b.length >= 3 && b[0] === 255 && b[1] === 216 && b[2] === 255)
    || (ext === 'png' && file.mimetype === 'image/png' && b.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')))
    || (ext === 'webp' && file.mimetype === 'image/webp' && b.length >= 12 && b.toString('ascii', 0, 4) === 'RIFF' && b.toString('ascii', 8, 12) === 'WEBP');
}

function createRecognitionRouter({ service = recognitionService, authenticate = auth,
  limiter = rateLimit({ windowMs: 60000, limit: 6, standardHeaders: 'draft-8', legacyHeaders: false,
    keyGenerator: req => String(req.auth.userId),
    message: { ok: false, code: 'RECOGNITION_RATE_LIMIT', message: 'Espera un minuto antes de realizar otra búsqueda.' } }) } = {}) {
  const router = express.Router();
  const upload = multer({ storage: multer.memoryStorage(),
    limits: { fileSize: MAX_BYTES, files: 1, fields: 0, parts: 2 } }).single('foto');
  router.post('/search', authenticate, limiter, (req, res, next) => {
    req.setTimeout(15000);
    upload(req, res, error => {
      req.setTimeout(0);
      if (error) return res.status(error.code === 'LIMIT_FILE_SIZE' ? 413 : 400).json({
        ok: false, code: error.code === 'LIMIT_FILE_SIZE' ? 'RECOGNITION_IMAGE_TOO_LARGE' : 'INVALID_RECOGNITION_IMAGE',
        message: 'Envía una sola foto JPG, JPEG, PNG o WEBP de máximo 5 MiB.' });
      if (!validImage(req.file)) return res.status(400).json({ ok: false,
        code: 'INVALID_RECOGNITION_IMAGE', message: 'Selecciona una foto JPG, JPEG, PNG o WEBP válida.' });
      return next();
    });
  }, async (req, res) => {
    const controller = new AbortController();
    const disconnect = () => { if (!res.writableEnded) controller.abort(); };
    res.once('close', disconnect);
    res.set('Cache-Control', 'no-store');
    try {
      const result = await service.search(req.file.buffer, { signal: controller.signal });
      if (!res.destroyed) res.json({ ok: true, ...result });
    } catch (error) {
      const known = {
        INVALID_RECOGNITION_IMAGE: [400, 'No se pudo leer la fotografía. Selecciona otra imagen.'],
        RECOGNITION_BUSY: [429, 'Hay una búsqueda en curso. Intenta nuevamente en unos segundos.'],
        RECOGNITION_TIMEOUT: [504, 'La búsqueda tardó demasiado. Intenta nuevamente.'],
      };
      const [status, message] = known[error.code] || [503, 'El reconocimiento no está disponible. Intenta nuevamente.'];
      if (!res.destroyed) res.status(status).json({ ok: false, code: known[error.code] ? error.code : 'RECOGNITION_UNAVAILABLE', message });
    } finally { res.removeListener('close', disconnect); }
  });
  return router;
}
module.exports = { createRecognitionRouter };
