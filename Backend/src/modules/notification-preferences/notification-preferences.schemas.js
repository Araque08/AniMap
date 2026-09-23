const { z } = require('zod');

const notificationPreferencesSchema = z
  .object({
    notificacionesActivas: z.boolean(),
    soloMiZona: z.boolean(),
    especieFiltro: z.enum(['Perro', 'Gato']).nullable(),
    tipoEvento: z.enum(['PERDIDA', 'AVISTAMIENTO', 'ENCONTRADO']).nullable(),
    radioKm: z.union([z.literal(1), z.literal(2), z.literal(5)]),
  })
  .strict();

module.exports = { notificationPreferencesSchema };
