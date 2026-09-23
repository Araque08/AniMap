const express = require('express');
const multer = require('multer');
const authMiddleware = require('../../middleware/auth.middleware');
const validateBody = require('../../middleware/validate.middleware');
const profileController = require('./profile.controller');
const { updateProfileSchema } = require('./profile.schemas');

const router = express.Router();
const MAX_PROFILE_PHOTO_BYTES = 5 * 1024 * 1024;
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_PROFILE_PHOTO_BYTES, files: 1 },
});

function isValidProfileImage(file) {
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

function uploadProfilePhoto(req, res, next) {
  upload.single('foto')(req, res, (error) => {
    if (error) {
      return res.status(400).json({
        ok: false,
        message: 'La foto debe pesar máximo 5 MB',
      });
    }
    if (!isValidProfileImage(req.file)) {
      return res.status(400).json({
        ok: false,
        message: 'Selecciona una imagen JPG, JPEG, PNG o WEBP válida',
      });
    }
    return next();
  });
}

function requireJson(req, res, next) {
  if (!req.is('application/json')) {
    return res.status(415).json({
      ok: false,
      message: 'Content-Type debe ser application/json',
    });
  }

  return next();
}

router.get('/', authMiddleware, profileController.getProfile);
router.get('/photo/:imageId', authMiddleware, profileController.getProfilePhoto);
router.post(
  '/photo',
  authMiddleware,
  uploadProfilePhoto,
  profileController.updateProfilePhoto
);

router.patch(
  '/',
  authMiddleware,
  requireJson,
  validateBody(updateProfileSchema),
  profileController.updateProfile
);

module.exports = router;
