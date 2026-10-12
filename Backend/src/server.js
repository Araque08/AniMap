const env = require('./config/env');
const app = require('./app');
const { pool } = require('./config/postgres_db');

async function startServer() {
  try {
    await pool.query('SELECT 1');
    app.listen(env.PORT, '0.0.0.0', () => {
      console.log(`Servidor corriendo en http://0.0.0.0:${env.PORT}`);
    });
  } catch (error) {
    console.error('No se pudo iniciar el servidor:', error);
    process.exit(1);
  }
}

startServer();
