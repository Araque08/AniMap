const { z } = require('zod');

/*
  Aquí hicimos los esquemas de validación para las peticiones de autenticación.

  Usamos Zod para validar que los datos lleguen con el formato correcto antes
  de que pasen al controlador o al servicio.
*/

/*
  Aquí definimos una política común para las contraseñas.

  La reutilizamos tanto en el registro como en la recuperación
  para mantener las mismas reglas de seguridad.
*/
const passwordSchema = z
  .string({ error: 'La contraseña es obligatoria' })
  .min(8, 'La contraseña debe tener mínimo 8 caracteres')
  .regex(/[A-Z]/, 'La contraseña debe incluir al menos una mayúscula')
  .regex(/[a-z]/, 'La contraseña debe incluir al menos una minúscula')
  .regex(/[0-9]/, 'La contraseña debe incluir al menos un número')
  .regex(
    /[^A-Za-z0-9]/,
    'La contraseña debe incluir al menos un carácter especial'
  );

/*
  Aquí validamos los datos necesarios para registrar un usuario.
*/
const registerSchema = z.object({
  /*
    Aquí validamos el nombre del usuario.

    Le pedimos mínimo 3 caracteres y máximo 120 para evitar nombres vacíos
    o textos demasiado largos.
  */
  nombre: z
    .string({ error: 'El nombre es obligatorio' })
    .trim()
    .min(3, 'El nombre es muy corto')
    .max(120),

  /*
    Aquí validamos el correo.

    También lo convertimos a minúsculas para evitar duplicados como
    correo@gmail.com y Correo@gmail.com.
  */
  email: z
    .string({ error: 'El correo es obligatorio' })
    .trim()
    .toLowerCase()
    .email('Correo no válido')
    .max(150),

  /*
    Aquí validamos el teléfono.

    Permitimos números, espacios, paréntesis, guiones y el símbolo +.
  */
  telefono: z
    .string({ error: 'El teléfono es obligatorio' })
    .trim()
    .min(10, 'Número de teléfono no válido')
    .max(20)
    .regex(
      /^[0-9+\-\s()]+$/,
      'Número de teléfono no válido'
    ),

  /*
    Aquí aplicamos la política de contraseñas definida anteriormente.
  */
  password: passwordSchema,

  /*
    Aquí obligamos a que el usuario acepte términos y condiciones.
  */
  aceptaTyC: z.literal(true, {
    error: 'Debes aceptar términos y condiciones',
  }),
});

/*
  Aquí validamos los datos del inicio de sesión.
*/
const loginSchema = z.object({
  /*
    Aquí validamos y normalizamos el correo.
  */
  email: z
    .string({ error: 'El correo es obligatorio' })
    .trim()
    .toLowerCase()
    .email('Correo no válido')
    .max(150),

  /*
    Aquí solamente comprobamos que venga una contraseña.

    La comparación con el hash se realiza posteriormente
    dentro del servicio.
  */
  password: z
    .string({ error: 'La contraseña es obligatoria' })
    .min(1, 'La contraseña es obligatoria')
    .max(100),

  /*
    Aquí permitimos recibir el identificador del dispositivo.
  */
  deviceId: z
    .string()
    .trim()
    .min(1)
    .max(120)
    .optional(),
});

const sessionTokenSchema = z
  .object({
    refreshToken: z
      .string({ error: 'El refresh token es obligatorio' })
      .trim()
      .min(1, 'El refresh token es obligatorio')
      .max(4096, 'Refresh token inválido'),
  })
  .strict();

/*
  Aquí validamos el correo y el código utilizado
  para verificar una cuenta nueva.
*/
const verifyAccountSchema = z.object({
  email: z
    .string({ error: 'El correo es obligatorio' })
    .trim()
    .toLowerCase()
    .email('Correo no válido')
    .max(150),

  code: z
    .string({ error: 'El código es obligatorio' })
    .trim()
    .regex(
      /^\d{6}$/,
      'Código de verificación inválido'
    ),
});

/*
  Aquí validamos el correo utilizado para solicitar
  un nuevo código de verificación de cuenta.
*/
const resendVerificationCodeSchema = z.object({
  email: z
    .string({ error: 'El correo es obligatorio' })
    .trim()
    .toLowerCase()
    .email('Correo no válido')
    .max(150),
});

/*
  RECUPERACIÓN DE CONTRASEÑA
*/

/*
  Aquí validamos la primera etapa de recuperación.

  El usuario solamente debe proporcionar su correo.
  Posteriormente el servicio buscará la cuenta y,
  cuando corresponda, enviará un código de recuperación.
*/
const forgotPasswordSchema = z.object({
  email: z
    .string({ error: 'El correo es obligatorio' })
    .trim()
    .toLowerCase()
    .email('Correo no válido')
    .max(150),
});

/*
  Aquí validamos la segunda etapa de recuperación.

  Necesitamos:
  - correo
  - código de recuperación
  - contraseña nueva
  - confirmación de la contraseña
*/
const resetPasswordSchema = z
  .object({
    email: z
      .string({ error: 'El correo es obligatorio' })
      .trim()
      .toLowerCase()
      .email('Correo no válido')
      .max(150),

    /*
      El código de recuperación tendrá exactamente 6 dígitos.
    */
    code: z
      .string({ error: 'El código es obligatorio' })
      .trim()
      .regex(
        /^\d{6}$/,
        'Código de recuperación inválido'
      ),

    /*
      Aplicamos exactamente la misma política utilizada
      durante el registro.
    */
    newPassword: passwordSchema,

    /*
      El usuario deberá escribir nuevamente la contraseña.
    */
    confirmPassword: passwordSchema,
  })

  /*
    Además comprobamos que ambas contraseñas sean iguales.
  */
  .refine(
    (data) => data.newPassword === data.confirmPassword,
    {
      message: 'Las contraseñas no coinciden',
      path: ['confirmPassword'],
    }
  );

/*
  Aquí exportamos todos los esquemas para utilizarlos
  en las rutas del módulo de autenticación.
*/
module.exports = {
  registerSchema,
  loginSchema,
  refreshSchema: sessionTokenSchema,
  logoutSchema: sessionTokenSchema,
  verifyAccountSchema,
  resendVerificationCodeSchema,
  forgotPasswordSchema,
  resetPasswordSchema,
};
