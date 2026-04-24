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
  Primero revisamos si las variables del .env están cargadas.
  Si no están cargadas, usamos modo prueba y mostramos el código en consola.
*/
async function sendVerificationCodeEmail({ to, code }) {
  const mailUser = process.env.MAIL_USER;
  const mailPass = process.env.MAIL_PASS;
  const mailFrom = process.env.MAIL_FROM || `AniMap <${mailUser}>`;

  console.log('[AniMap] Intentando enviar código de verificación...');
  console.log('[AniMap] MAIL_USER configurado:', Boolean(mailUser));
  console.log('[AniMap] MAIL_PASS configurado:', Boolean(mailPass));
  console.log('[AniMap] Destinatario:', to);

  if (!mailUser || !mailPass) {
    console.log('[AniMap] No hay credenciales SMTP configuradas. Usando modo prueba.');
    console.log(`[AniMap] Código de verificación para ${to}: ${code}`);
    return;
  }

  try {
    const transporter = getTransporter();

    const info = await transporter.sendMail({
      from: mailFrom,
      to,
      subject: 'Código de verificación - AniMap',
      html: `
        <div style="font-family: Arial, sans-serif; color: #415466; max-width: 520px; margin: 0 auto;">
          <h2 style="color: #3F9E57;">AniMap</h2>
          <p>Hola,</p>
          <p>Tu código de verificación es:</p>
          <h1 style="letter-spacing: 6px; color: #3F9E57;">${code}</h1>
          <p>Este código vence en 15 minutos.</p>
          <p>Si no creaste esta cuenta, ignora este mensaje.</p>
        </div>
      `,
      text: `Tu código de verificación de AniMap es: ${code}. Este código vence en 15 minutos.`,
    });

    console.log('[AniMap] Correo de verificación enviado correctamente.');
    console.log('[AniMap] Message ID:', info.messageId);
  } catch (error) {
    console.error('[AniMap] Error enviando correo de verificación:');
    console.error(error);
    throw error;
  }
}

/*
  Aquí exportamos la función para usarla desde el servicio de autenticación.
*/
module.exports = {
  sendVerificationCodeEmail,
};