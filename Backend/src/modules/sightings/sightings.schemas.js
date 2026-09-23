const { z } = require('zod');

const optionalReportId = z.preprocess(
  (value) => value === undefined || value === null || value === '' ? null : Number(value),
  z.number().int().positive('El reporte seleccionado no es válido').nullable()
);

const optionalAccuracy = z.preprocess(
  (value) => value === undefined || value === null || value === '' ? null : Number(value),
  z.number().min(0).max(100000).nullable()
);

const optionalText = (max) => z.preprocess(
  (value) => value === undefined || value === null || value === '' ? null : value,
  z.string().trim().max(max).nullable()
);

const createSightingSchema = z.object({
  descripcion: z.string().trim().min(1, 'La descripción es obligatoria').max(2000),
  reportId: optionalReportId,
  metodo: z.enum(['GPS', 'MAPA', 'DIRECCION']),
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  precisionM: optionalAccuracy,
  direccion: optionalText(255),
  placeId: optionalText(150),
}).strict().superRefine((sighting, context) => {
  if (sighting.metodo !== 'DIRECCION') return;
  if (!sighting.direccion) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['direccion'],
      message: 'La dirección validada es obligatoria',
    });
  }
  if (!sighting.placeId) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['placeId'],
      message: 'El identificador de la dirección validada es obligatorio',
    });
  }
});

const historyPeriodSchema = z.enum(['ALL', 'TODAY', '7D', '30D']);

module.exports = { createSightingSchema, historyPeriodSchema };
