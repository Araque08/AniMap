const { z } = require('zod');

const geocodeAddressSchema = z.object({
  address: z.string().trim().min(1).max(300),
}).strict();

module.exports = { geocodeAddressSchema };
