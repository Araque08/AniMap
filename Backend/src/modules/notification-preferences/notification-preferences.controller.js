const {
  notificationPreferencesService,
} = require('./notification-preferences.service');

async function getPreferences(req, res, next) {
  try {
    const preferences = await notificationPreferencesService.getPreferences(
      req.auth.userId
    );
    return res.status(200).json({ ok: true, data: preferences });
  } catch (error) {
    return next(error);
  }
}

async function updatePreferences(req, res, next) {
  try {
    const preferences = await notificationPreferencesService.updatePreferences(
      req.auth.userId,
      req.validatedBody
    );
    return res.status(200).json({
      ok: true,
      message: 'Preferencias guardadas correctamente',
      data: preferences,
    });
  } catch (error) {
    return next(error);
  }
}

module.exports = { getPreferences, updatePreferences };
