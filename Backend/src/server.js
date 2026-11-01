const env = require('./config/env');
const app = require('./app');
const { pool } = require('./config/postgres_db');
const { notificationsService } = require('./modules/notifications/notifications.service');

async function startServer() {
  try {
    await pool.query('SELECT 1');
    app.listen(env.PORT, '0.0.0.0', () => {
      console.log(`Servidor corriendo en http://0.0.0.0:${env.PORT}`);
      notificationsService.start();
    });
  } catch (error) {
    console.error('No se pudo iniciar el servidor:', error);
    process.exit(1);
  }
}

startServer();
