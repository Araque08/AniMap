const geofence = require('./geofence.service');

function check(req, res) {
  const { lat, lng } = req.validatedBody;
  return res.status(200).json(geofence.evaluateAllowedArea(lat, lng));
}

module.exports = { check };
