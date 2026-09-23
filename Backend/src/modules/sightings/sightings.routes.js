const express = require('express');
const multer = require('multer');
const authMiddleware = require('../../middleware/auth.middleware');
const validateBody = require('../../middleware/validate.middleware');
const controller = require('./sightings.controller');
const { createSightingSchema } = require('./sightings.schemas');

const router = express.Router();
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_PHOTO_BYTES, files: 1, fields: 8, fieldSize: 10 * 1024 },
});

function validImage(file) {
  if (!file?.buffer?.length) return false;
  const extension = file.originalname.split('.').pop()?.toLowerCase();
  const bytes = file.buffer;
  if (file.mimetype === 'image/jpeg' && ['jpg', 'jpeg'].includes(extension)) {
    return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  }
  if (file.mimetype === 'image/png' && extension === 'png') {
    return bytes.length >= 8 && bytes.subarray(0, 8).equals(
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    );
  }
  if (file.mimetype === 'image/webp' && extension === 'webp') {
    return bytes.length >= 12 && bytes.toString('ascii', 0, 4) === 'RIFF' &&
      bytes.toString('ascii', 8, 12) === 'WEBP';
  }
  return false;
}

function uploadOptionalPhoto(req, res, next) {
  upload.single('foto')(req, res, (error) => {
    if (error) {
      const tooLarge = error.code === 'LIMIT_FILE_SIZE';
      return res.status(400).json({
        ok: false,
        message: tooLarge
          ? 'La foto debe pesar máximo 5 MB'
          : 'Solo se permite una foto opcional',
      });
    }
    if (req.file && !validImage(req.file)) {
      return res.status(400).json({
        ok: false,
        message: 'Selecciona una imagen JPG, JPEG, PNG o WEBP válida',
      });
    }
    return next();
  });
}

router.get('/linkable-reports', controller.listLinkableReports);
router.get('/images/:imageId', controller.getPublicImage);
router.get('/:id', controller.getPublicSighting);
router.post(
  '/',
  authMiddleware,
  uploadOptionalPhoto,
  validateBody(createSightingSchema),
  controller.createSighting
);

module.exports = router;
