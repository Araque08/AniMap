const nodemailer = require('nodemailer');

function getTransporter() {
  return nodemailer.createTransport({
    host: process.env.MAIL_HOST,
    port: Number(process.env.MAIL_PORT || 587),
    secure: process.env.MAIL_SECURE === 'true',
    auth: {
      user: process.env.MAIL_USER,
      pass: process.env.MAIL_PASS,
    },
  });
}

async function sendVerificationCodeEmail({ to, code }) {
  if (!process.env.MAIL_USER || !process.env.MAIL_PASS) {
    console.log(`[AniMap] Código de verificación para ${to}: ${code}`);
    return;
  }

  const transporter = getTransporter();

  await transporter.sendMail({
    from: process.env.MAIL_FROM || process.env.MAIL_USER,
    to,
    subject: 'Código de verificación - AniMap',
    html: `
      <div style="font-family: Arial, sans-serif; color: #415466;">
        <h2>AniMap</h2>
        <p>Tu código de verificación es:</p>
        <h1 style="letter-spacing: 6px;">${code}</h1>
        <p>Este código vence en 15 minutos.</p>
        <p>Si no creaste esta cuenta, ignora este mensaje.</p>
      </div>
    `,
  });
}

module.exports = {
  sendVerificationCodeEmail,
};