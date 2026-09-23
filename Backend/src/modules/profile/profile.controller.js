const profileService = require('./profile.service');

async function getProfile(req, res, next) {
  try {
    const profile = await profileService.getProfile(req.auth.userId);

    return res.status(200).json({
      ok: true,
      data: profile,
    });
  } catch (error) {
    return next(error);
  }
}

async function updateProfile(req, res, next) {
  try {
    const profile = await profileService.updateProfile(
      req.auth.userId,
      req.validatedBody
    );

    return res.status(200).json({
      ok: true,
      message: 'Perfil actualizado correctamente',
      data: profile,
    });
  } catch (error) {
    return next(error);
  }
}

async function updateProfilePhoto(req, res, next) {
  try {
    const profile = await profileService.updateProfilePhoto(
      req.auth.userId,
      req.file
    );
    return res.status(200).json({
      ok: true,
      message: 'Foto de perfil actualizada correctamente',
      data: profile,
    });
  } catch (error) {
    return next(error);
  }
}

async function getProfilePhoto(req, res, next) {
  try {
    const image = await profileService.getProfilePhoto(
      req.auth.userId,
      req.params.imageId
    );
    res.set('Content-Type', image.mimeType);
    res.set('Cache-Control', 'private, no-store');
    return res.send(image.buffer);
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  getProfilePhoto,
  getProfile,
  updateProfile,
  updateProfilePhoto,
};
