const { z } = require('zod');

const locationSchema = z.object({
  metodo: z.enum(['GPS', 'MAPA', 'DIRECCION']),
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  precisionM: z.coerce.number().min(0).max(100000).nullable().optional(),
  direccion: z.string().trim().max(255).nullable().optional(),
  placeId: z.string().trim().max(150).nullable().optional(),
}).superRefine((location, context) => {
  if (location.metodo !== 'DIRECCION') return;
  if (!location.direccion) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['direccion'],
      message: 'La dirección validada es obligatoria',
    });
  }
  if (!location.placeId) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['placeId'],
      message: 'El identificador de la dirección validada es obligatorio',
    });
  }
});

const createReportSchema = z.object({
  mascotaId: z.coerce.number().int().positive(),
  descripcion: z.string().trim().max(2000).nullable().optional(),
  mostrarContacto: z.boolean().optional().default(false),
  ubicacion: locationSchema,
});

const updateReportSchema = z
  .object({
    descripcion: z.string().trim().max(2000).nullable().optional(),
    mostrarContacto: z.boolean().optional(),
    ubicacion: locationSchema.optional(),
  })
  .refine(
    (data) => Object.keys(data).length > 0,
    'Debes enviar al menos un campo para actualizar'
  );

module.exports = {
  createReportSchema,
  updateReportSchema,
};
