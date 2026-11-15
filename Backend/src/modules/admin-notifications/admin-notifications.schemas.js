
const { z } = require('zod');

const {
  BARRIOS_NOTIFICACIONES
} = require('../notification-preferences/notification-preferences.schemas');

// HU-049: Validación del comunicado administrativo.
const enviarNotificacionSchema = z.object({
  titulo: z.string()
    .trim()
    .min(3, 'El título debe tener mínimo 3 caracteres')
    .max(140, 'El título no puede superar 140 caracteres'),

  mensaje: z.string()
    .trim()
    .min(5, 'El mensaje debe tener mínimo 5 caracteres')
    .max(1000, 'El mensaje no puede superar 1000 caracteres'),

  audiencia: z.enum([
    'TODOS',
    'USUARIO',
    'ADMINISTRADOR'
  ]),

  // Opcional: null significa todos los barrios.
  barrio: z.enum(BARRIOS_NOTIFICACIONES)
    .nullable()
    .optional()
}).strict();

module.exports = {
  enviarNotificacionSchema
};
