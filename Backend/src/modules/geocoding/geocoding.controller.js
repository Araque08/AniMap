const { geocodeAddressSchema } = require('./geocoding.schemas');
const { geocodingService, messages } = require('./geocoding.service');

async function geocodeAddress(req, res, next) {
  const parsed = geocodeAddressSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({
      ok: false,
      code: 'ADDRESS_REQUIRED',
      message: messages.ADDRESS_REQUIRED,
    });
  }
  try {
    const result = await geocodingService.geocodeAddress(parsed.data.address);
    return res.status(200).json({ ok: true, ...result });
  } catch (error) {
    return next(error);
  }
}

module.exports = { geocodeAddress };
