
const { z } = require('zod');

// =====================================================
// CATÁLOGO DE BARRIOS PARA NOTIFICACIONES
// =====================================================

const BARRIOS_NOTIFICACIONES = [
  'Ciudad Salitre Occidental',
  'Ciudad Salitre Nor-Occidental',
  'El Salitre',
  'Marsella',
  'Modelia',
  'Modelia Occidental',
  'Normandía Occidental',
  'La Esperanza Norte',
  'La Esperanza Sur',
  'Montevideo',
  'Granjas de Techo',
  'Villa Alsacia',
];

// =====================================================
// VALIDACIÓN DE PREFERENCIAS
// =====================================================

const notificationPreferencesSchema = z
  .object({
    notificacionesActivas: z.boolean(),

    soloMiZona: z.boolean(),

    especieFiltro: z
      .enum(['Perro', 'Gato'])
      .nullable(),

    tipoEvento: z
      .enum([
        'PERDIDA',
        'AVISTAMIENTO',
        'ENCONTRADO',
      ])
      .nullable(),

    radioKm: z.union([
      z.literal(1),
      z.literal(2),
      z.literal(5),
    ]),

    // HU-049: Barrio para notificaciones.
    barrioNotificaciones: z
      .enum(BARRIOS_NOTIFICACIONES)
      .nullable()
      .optional(),

    // =================================================
    // HU-064: UBICACIÓN DE REFERENCIA
    // =================================================

    // Son opcionales para mantener compatibilidad
    // con versiones anteriores de Flutter.

    latReferencia: z
      .number()
      .min(-90)
      .max(90)
      .nullable()
      .optional(),

    lngReferencia: z
      .number()
      .min(-180)
      .max(180)
      .nullable()
      .optional(),
  })
  .strict()
  .superRefine((data, ctx) => {
    const tieneLat = Object.hasOwn(
      data,
      'latReferencia'
    );

    const tieneLng = Object.hasOwn(
      data,
      'lngReferencia'
    );

    // Ambas coordenadas deben enviarse juntas.
    if (tieneLat !== tieneLng) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'Debes enviar ambas coordenadas.',
        path: ['latReferencia'],
      });
      return;
    }

    // Se permiten dos números o dos valores null.
    if (
      tieneLat &&
      (data.latReferencia === null) !==
        (data.lngReferencia === null)
    ) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message:
          'Las coordenadas deben tener valores válidos o ambas ser null.',
        path: ['latReferencia'],
      });
    }
  });

// =====================================================
// EXPORTACIONES
// =====================================================

module.exports = {
  notificationPreferencesSchema,
  BARRIOS_NOTIFICACIONES,
};
