const { z } = require('zod');

const checkGeofenceSchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
}).strict();

module.exports = { checkGeofenceSchema };
