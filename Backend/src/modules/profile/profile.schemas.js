const { z } = require('zod');

const phoneSchema = z
  .string()
  .trim()
  .min(10, 'Número de teléfono no válido')
  .max(20, 'Número de teléfono no válido')
  .regex(/^[0-9+\-\s()]+$/, 'Número de teléfono no válido');

const updateProfileSchema = z
  .object({
    nombre: z.string().trim().min(3, 'El nombre es muy corto').max(120).optional(),
    telefono: phoneSchema.optional(),
    email: z
      .unknown()
      .refine(() => false, 'El correo electrónico no se puede modificar')
      .optional(),
  })
  .strict()
  .refine(
    (data) => data.nombre !== undefined || data.telefono !== undefined,
    'Debes enviar al menos un campo editable'
  );

module.exports = {
  updateProfileSchema,
};
