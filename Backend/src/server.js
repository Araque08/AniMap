const app = require('./app');
const env = require('./config/env');
const { pool } = require('./config/postgres_db');

async function startServer() {
  try {
    await pool.query('SELECT 1');
    const PORT = process.env.PORT || 3000;

    /*app.listen(env.PORT, () => {
      console.log(`Servidor corriendo en http://localhost:${env.PORT}`);
    });*/
    app.listen(PORT, '0.0.0.0', () => {
    console.log(`Servidor corriendo en http://0.0.0.0:${PORT}`);
});
  } catch (error) {
    console.error('No se pudo iniciar el servidor:', error);
    process.exit(1);
  }
}

startServer();