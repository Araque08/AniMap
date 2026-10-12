const db = require('../../config/postgres_db');
const images = require('./pets.images.repository');

function createPetDeletionRecovery({ pool = db.pool, repository = images, logger = console } = {}) {
  async function recover(operationId) {
    let client;
    let discardClient = false;
    try {
      let operation = await repository.getPetPhotoRecovery(operationId);
      if (!operation) return { ok: true, outcome: 'ALREADY_RESOLVED' };
      client = await pool.connect();
      await client.query('BEGIN');
      const result = await client.query(
        `SELECT id, estado FROM mascota WHERE id = $1 AND fk_usuario = $2 FOR UPDATE`,
        [operation.mascotaId, operation.usuarioId]
      );
      if (result.rowCount !== 1) throw Object.assign(new Error(), { code: 'PET_PHOTO_OWNER_NOT_FOUND' });
      const lockedOperation = await repository.getPetPhotoRecovery(operationId);
      if (!lockedOperation) {
        await client.query('COMMIT');
        return { ok: true, outcome: 'ALREADY_RESOLVED' };
      }
      if (lockedOperation.mascotaId !== operation.mascotaId || lockedOperation.usuarioId !== operation.usuarioId) {
        throw Object.assign(new Error(), { code: 'PET_PHOTO_RECOVERY_CONFLICT' });
      }
      operation = lockedOperation;
      const estado = result.rows[0].estado;
      const outcome = await repository.reconcilePetPhotos(operation, estado);
      const confirmed = await client.query(
        `SELECT id, estado FROM mascota WHERE id = $1 AND fk_usuario = $2`,
        [operation.mascotaId, operation.usuarioId]
      );
      if (confirmed.rows[0]?.estado !== estado) throw Object.assign(new Error(), { code: 'PET_PHOTO_STATE_UNCONFIRMED' });
      if (operation.phase === 'PREPARING' || operation.phase === 'RESOLVED') {
        await repository.cleanupPetPhotoRecovery(operation);
      } else {
        await repository.resolvePetPhotoRecovery(operation, outcome);
      }
      await client.query('COMMIT');
      return { ok: true, outcome };
    } catch (error) {
      if (client) {
        await client.query('ROLLBACK').catch(() => { discardClient = true; });
      }
      const code = /^PET_PHOTO_[A-Z_]+$/.test(error.code || '')
        ? error.code : 'PET_PHOTO_RECOVERY_UNAVAILABLE';
      // Never log driver messages, BSON documents, images, connection URLs or credentials.
      logger.error('PET_PHOTO_RECOVERY_PENDING', { operationId, code });
      return { ok: false, operationId, code };
    } finally {
      client?.release(discardClient);
    }
  }
  return { recover };
}

module.exports = { createPetDeletionRecovery, petDeletionRecovery: createPetDeletionRecovery() };
