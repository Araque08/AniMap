const nodemailer = require('nodemailer');

/*
  Aquí hicimos la configuración del transportador de correo.
  Tomamos los datos desde variables de entorno para no dejar credenciales
  escritas directamente en el código.
*/
function getTransporter() {
  return nodemailer.createTransport({
    host: process.env.MAIL_HOST || 'smtp.gmail.com',
    port: Number(process.env.MAIL_PORT || 587),
    secure: process.env.MAIL_SECURE === 'true',
    auth: {
      user: process.env.MAIL_USER,
      pass: process.env.MAIL_PASS,
    },
  });
}

/*
  Aquí hicimos la función que envía el código de verificación al correo.
  Si la configuración está incompleta, falla sin exponer el código.
*/
async function sendVerificationCodeEmail({ to, code }) {
  const mailUser = process.env.MAIL_USER;
  const mailPass = process.env.MAIL_PASS;
  const mailFrom = process.env.MAIL_FROM || `AniMap <${mailUser}>`;

  if (!mailUser || !mailPass) {
    throw new Error('Configuración SMTP incompleta');
  }

  try {
    const transporter = getTransporter();

    await transporter.sendMail({
      from: mailFrom,
      to,
      subject: 'Código de verificación - AniMap',
      html: `
        <div style="font-family: Arial, sans-serif; color: #415466; max-width: 520px; margin: 0 auto;">
          <h2 style="color: #3F9E57;">AniMap</h2>

          <p>Hola,</p>

          <p>Tu código de verificación es:</p>

          <h1 style="letter-spacing: 6px; color: #3F9E57;">
            ${code}
          </h1>

          <p>Este código vence en 15 minutos.</p>

          <p>Si no creaste esta cuenta, ignora este mensaje.</p>
        </div>
      `,
      text: `Tu código de verificación de AniMap es: ${code}. Este código vence en 15 minutos.`,
    });

  } catch (_) {
    console.error('[AniMap] No se pudo enviar el correo de verificación.');
    throw new Error('No se pudo enviar el correo de verificación');
  }
}

/*
  Aquí hicimos la función que envía el código para recuperar la contraseña.

  Este código es diferente al código utilizado para verificar una cuenta nueva.

  El servicio de autenticación será el encargado de generar el código,
  guardar únicamente su hash en PostgreSQL y controlar su expiración.
*/
async function sendPasswordResetCodeEmail({ to, code }) {
  const mailUser = process.env.MAIL_USER;
  const mailPass = process.env.MAIL_PASS;
  const mailFrom = process.env.MAIL_FROM || `AniMap <${mailUser}>`;

  if (!mailUser || !mailPass) {
    throw new Error('Configuración SMTP incompleta');
  }

  try {
    const transporter = getTransporter();

    await transporter.sendMail({
      from: mailFrom,
      to,
      subject: 'Recuperación de contraseña - AniMap',

      html: `
        <div style="
          font-family: Arial, sans-serif;
          color: #415466;
          max-width: 520px;
          margin: 0 auto;
        ">

          <h2 style="color: #3F9E57;">
            AniMap
          </h2>

          <p>Hola,</p>

          <p>
            Recibimos una solicitud para recuperar la contraseña
            de tu cuenta de AniMap.
          </p>

          <p>
            Tu código de recuperación es:
          </p>

          <h1 style="
            letter-spacing: 6px;
            color: #3F9E57;
          ">
            ${code}
          </h1>

          <p>
            Este código vence en 15 minutos.
          </p>

          <p>
            Si tú no solicitaste recuperar tu contraseña,
            puedes ignorar este mensaje.
          </p>

          <p>
            Por seguridad, no compartas este código con nadie.
          </p>

        </div>
      `,

      text:
        `Recibimos una solicitud para recuperar tu contraseña de AniMap. ` +
        `Tu código de recuperación es: ${code}. ` +
        `Este código vence en 15 minutos. ` +
        `Si no solicitaste este cambio, ignora este mensaje.`,
    });

  } catch (_) {
    console.error('[AniMap] No se pudo enviar el correo de recuperación.');
    throw new Error('No se pudo enviar el correo de recuperación');
  }
}

/*
  Aquí exportamos las funciones para utilizarlas
  desde el servicio de autenticación.
*/
module.exports = {
  sendVerificationCodeEmail,
  sendPasswordResetCodeEmail,
};
