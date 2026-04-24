const { z } = require('zod');

const registerSchema = z.object({
  nombre: z.string().trim().min(3, 'El nombre es muy corto').max(120),
  email: z.string().trim().toLowerCase().email('Correo no válido').max(150),
  telefono: z
    .string()
    .trim()
    .min(10, 'Número de teléfono no válido')
    .max(20)
    .regex(/^[0-9+\-\s()]+$/, 'Número de teléfono no válido'),
  password: z.string().min(8, 'La contraseña debe tener mínimo 8 caracteres').max(100),
  aceptaTyC: z.literal(true, {
    errorMap: () => ({
      message: 'Debes aceptar términos y condiciones',
    }),
  }),
});

const loginSchema = z.object({
  email: z.string().trim().toLowerCase().email('Correo no válido').max(150),
  password: z.string().min(1, 'La contraseña es obligatoria').max(100),
  deviceId: z.string().trim().min(1).max(120).optional(),
});

module.exports = {
  registerSchema,
  loginSchema,
};