const { z } = require('zod');

/*
  Aquí hicimos los esquemas de validación para las peticiones de autenticación.
  Usamos Zod para validar que los datos lleguen con el formato correcto antes
  de que pasen al controlador o al servicio.
*/

const registerSchema = z.object({
  /*
    Aquí validamos el nombre del usuario.
    Le pedimos mínimo 3 caracteres y máximo 120 para evitar nombres vacíos
    o textos demasiado largos.
  */
  nombre: z.string().trim().min(3, 'El nombre es muy corto').max(120),

  /*
    Aquí validamos el correo.
    También lo convertimos a minúsculas para evitar duplicados como
    correo@gmail.com y Correo@gmail.com.
  */
  email: z.string().trim().toLowerCase().email('Correo no válido').max(150),

  /*
    Aquí validamos el teléfono.
    Permitimos números, espacios, paréntesis, guiones y el símbolo +.
  */
  telefono: z
    .string()
    .trim()
    .min(10, 'Número de teléfono no válido')
    .max(20)
    .regex(/^[0-9+\-\s()]+$/, 'Número de teléfono no válido'),

  /*
    Aquí validamos la contraseña.
    Definimos mínimo 8 caracteres para mejorar la seguridad básica del registro.
  */
  password: z
    .string()
    .min(8, 'La contraseña debe tener mínimo 8 caracteres')
    .max(100),

  /*
    Aquí obligamos a que el usuario acepte términos y condiciones.
    Solo permitimos el valor true.
  */
  aceptaTyC: z.literal(true, {
    errorMap: () => ({
      message: 'Debes aceptar términos y condiciones',
    }),
  }),
});

const loginSchema = z.object({
  /*
    Aquí validamos el correo del inicio de sesión.
    También lo normalizamos a minúsculas para buscarlo correctamente en la base.
  */
  email: z.string().trim().toLowerCase().email('Correo no válido').max(150),

  /*
    Aquí validamos que la contraseña venga en la petición.
    No revisamos aquí si es correcta; eso se hace luego comparando el hash.
  */
  password: z.string().min(1, 'La contraseña es obligatoria').max(100),

  /*
    Aquí permitimos recibir el identificador del dispositivo.
    Esto nos sirve para manejar sesiones por dispositivo.
  */
  deviceId: z.string().trim().min(1).max(120).optional(),
});

const verifyAccountSchema = z.object({
  /*
    Aquí validamos el correo de la cuenta que se quiere verificar.
  */
  email: z.string().trim().toLowerCase().email('Correo no válido').max(150),

  /*
    Aquí validamos que el código tenga exactamente 6 dígitos numéricos.
  */
  code: z
    .string()
    .trim()
    .regex(/^\d{6}$/, 'Código de verificación inválido'),
});

const resendVerificationCodeSchema = z.object({
  /*
    Aquí validamos el correo al que se le reenviará el código de verificación.
  */
  email: z.string().trim().toLowerCase().email('Correo no válido').max(150),
});

/*
  Aquí exportamos los esquemas para usarlos en las rutas de autenticación.
*/
module.exports = {
  registerSchema,
  loginSchema,
  verifyAccountSchema,
  resendVerificationCodeSchema,
};