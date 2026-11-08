const env = require('./config/env');
const app = require('./app');
const { pool } = require('./config/postgres_db');
const { notificationsService } = require('./modules/notifications/notifications.service');
const { closeMongoDb } = require('./config/mongo_db');

async function startServer({ application = app, database = pool, worker = notificationsService,
  closeImages = closeMongoDb, signals = process, exit = code => process.exit(code) } = {}) {
  await database.query('SELECT 1');
  const server = application.listen(env.PORT, '0.0.0.0');
  await new Promise((resolve, reject) => {
    server.once('listening', resolve); server.once('error', reject);
  });
  worker.start();
  let closing;
  function shutdown() {
    if (closing) return closing;
    worker.stop();
    const deadline = setTimeout(() => exit(1), 9000);
    deadline.unref();
    closing = new Promise(resolve => server.close(resolve)).then(async () => {
      const results = await Promise.allSettled([database.end(), closeImages()]);
      clearTimeout(deadline);
      signals.removeListener('SIGTERM', shutdown);
      signals.removeListener('SIGINT', shutdown);
      exit(results.some(result => result.status === 'rejected') ? 1 : 0);
    });
    return closing;
  }
  signals.once('SIGTERM', shutdown);
  signals.once('SIGINT', shutdown);
  return { server, shutdown };
}

if (require.main === module) {
  startServer().then(() => console.log(`AniMap API escuchando en puerto ${env.PORT}`))
    .catch(() => { console.error('No se pudo iniciar AniMap; revisa dependencias y configuración.'); process.exit(1); });
}

module.exports = { startServer };
