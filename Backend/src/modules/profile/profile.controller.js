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

module.exports = {
  getProfile,
  updateProfile,
};
