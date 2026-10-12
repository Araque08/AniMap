// Explicit operator command; never runs automatically at startup or via HTTP.
const operationId = process.argv[2];
if (process.argv.length !== 3 || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(operationId || '')) {
  console.error('Uso: node scripts/recover-pet-deletion.js <operationId UUID>');
  process.exitCode = 1;
} else {
  (async () => {
    let pool;
    let mongo;
    try {
      require('../src/config/env');
      pool = require('../src/config/postgres_db').pool;
      mongo = await require('../src/config/mongo_db').getMongoDb();
      const { petDeletionRecovery } = require('../src/modules/pets/pets.deletion-recovery.service');
      const result = await petDeletionRecovery.recover(operationId);
      console.log(JSON.stringify({ operationId, ...result }));
      process.exitCode = result.ok ? 0 : 1;
    } catch (_) {
      console.error('PET_PHOTO_RECOVERY_START_FAILED', { operationId });
      process.exitCode = 1;
    } finally {
      if (pool) await pool.end().catch(() => { process.exitCode = 1; });
      if (mongo) await mongo.client.close().catch(() => { process.exitCode = 1; });
    }
  })();
}
