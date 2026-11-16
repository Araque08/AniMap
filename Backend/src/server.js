const env = require('./config/env');
const app = require('./app');
const { pool } = require('./config/postgres_db');
const { closeMongoDb } = require('./config/mongo_db');
const { notificationsService } = require('./modules/notifications/notifications.service');

// HU-049: programadores de notificaciones administrativas.
const {
  createAdminQAScheduler,
} = require('./modules/admin-notifications/admin-notifications.delivery.scheduler');
const {
  createAdminGeneralScheduler,
} = require('./modules/admin-notifications/admin-notifications.delivery.general.scheduler');

const adminQAScheduler = createAdminQAScheduler();
const adminGeneralScheduler = createAdminGeneralScheduler();

// Conservar la inyección de dependencias introducida en dev para las pruebas
// del ciclo de vida del servidor.
async function startServer({
  application = app,
  database = pool,
  worker = notificationsService,
  analyzer,
  qaScheduler = adminQAScheduler,
  generalScheduler = adminGeneralScheduler,
  closeImages = closeMongoDb,
  signals = process,
  exit = code => process.exit(code),
} = {}) {
  await database.query('SELECT 1');

  const server = application.listen(env.PORT, '0.0.0.0');
  await new Promise((resolve, reject) => {
    server.once('listening', resolve);
    server.once('error', reject);
  });

  const photoAnalyzer = analyzer === undefined && worker === notificationsService
    ? require('./modules/recognition/recognition.matches.service').matchService : analyzer;
  photoAnalyzer?.start();
  worker.start();
  // HU-049: iniciar los programadores administrativos.
  qaScheduler.start();
  generalScheduler.start();

  let closing;
  function shutdown() {
    if (closing) return closing;

    photoAnalyzer?.stop();
    worker.stop();
    // Detener también los temporizadores administrativos, si sus
    // implementaciones exponen stop().
    qaScheduler.stop?.();
    generalScheduler.stop?.();

    const deadline = setTimeout(() => exit(1), 9000);
    deadline.unref();

    closing = new Promise(resolve => server.close(resolve)).then(async () => {
      const results = await Promise.allSettled([
        database.end(),
        closeImages(),
      ]);
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
  startServer()
    .then(() => console.log(`AniMap API escuchando en puerto ${env.PORT}`))
    .catch((error) => {
      console.error('ERROR REAL AL INICIAR ANIMAP:');
      console.error(error);
      process.exit(1);
    });

}

module.exports = { startServer };
