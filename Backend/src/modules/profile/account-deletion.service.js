'use strict';

/**
 * HU-006 — Eliminación de la cuenta del propio usuario.
 * Se llama EXCLUSIVAMENTE desde una ruta protegida con authMiddleware
 * usando req.auth.userId. No aceptar un userId enviado por el cliente.
 *
 * Precaución técnica: PostgreSQL y MongoDB no comparten una transacción.
 * Este servicio intenta compensar fallos restaurando imágenes desde una
 * copia temporal en memoria, pero no garantiza recuperación ante caída
 * del proceso. Probar con cuentas ficticias antes de habilitar en producción.
 */
const postgres = require('../../config/postgres_db');
const { getMongoDb } = require('../../config/mongo_db');
const { compareHash } = require('../../utils/hash');

const IMAGE_COLLECTIONS = [
  'ImagenPerfil',
  'ImagenMascota',
  'ImagenAvistamiento',
];

function userError(message, statusCode, code) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.code = code;
  return error;
}

async function restoreImages(mongo, userId, backups) {
  const problems = [];
  for (const name of IMAGE_COLLECTIONS) {
    const documents = backups.get(name) || [];
    if (documents.length === 0) continue;
    try {
      const collection = mongo.collection(name);
      for (const original of documents) {
        await collection.replaceOne(
          { _id: original._id, usuarioIdPg: userId },
          original,
          { upsert: true }
        );
      }
    } catch (error) {
      problems.push(name);
    }
  }
  return problems;
}

async function deleteOwnAccount(userId, password) {
  if (!Number.isInteger(userId) || userId <= 0) {
    throw userError('Sesión inválida', 401, 'INVALID_SESSION');
  }
  if (typeof password !== 'string' || !password) {
    throw userError('Debes confirmar tu contraseña', 400, 'PASSWORD_REQUIRED');
  }

  const client = await postgres.pool.connect();
  let transactionStarted = false;
  let committed = false;
  let mongo = null;
  let mongoModified = false;
  const backups = new Map();

  try {
    await client.query('BEGIN');
    transactionStarted = true;

    // El identificador proviene exclusivamente del middleware autenticado.
    const result = await client.query(
      `SELECT id, password_hash, estado_cuenta
       FROM usuario WHERE id = $1 FOR UPDATE`,
      [userId]
    );
    if (result.rowCount !== 1 || result.rows[0].estado_cuenta !== 'ACTIVO') {
      throw userError('La cuenta no está disponible', 404, 'ACCOUNT_NOT_FOUND');
    }

    const correctPassword = await compareHash(password, result.rows[0].password_hash);
    if (!correctPassword) {
      throw userError('Contraseña incorrecta', 403, 'INVALID_PASSWORD');
    }

    // Un usuario que haya sido administrador puede aparecer como autor
    // de acciones en la bitácora administrativa (FK con ON DELETE RESTRICT).
    // No alteramos ni borramos registros de auditoría para sortear el bloqueo.
    const audit = await client.query(
      `SELECT EXISTS (
         SELECT 1 FROM bitacora_administrativa WHERE fk_admin = $1
       ) AS existe`,
      [userId]
    );
    if (audit.rows[0]?.existe) {
      throw userError(
        'La cuenta tiene registros de auditoría que deben revisarse antes de su eliminación.',
        409,
        'AUDIT_HISTORY_RESTRICTS_DELETE'
      );
    }

    // Comprobar MongoDB ANTES de modificar datos. El resto de PostgreSQL
    // se eliminará en cascada según las claves foráneas actuales.
    mongo = await getMongoDb();
    await mongo.command({ ping: 1 });
    for (const name of IMAGE_COLLECTIONS) {
      const documents = await mongo
        .collection(name)
        .find({ usuarioIdPg: userId })
        .toArray();
      backups.set(name, documents);
    }

    const deletion = await client.query(
      'DELETE FROM usuario WHERE id = $1 RETURNING id',
      [userId]
    );
    if (deletion.rowCount !== 1) {
      throw userError('La cuenta no pudo eliminarse', 409, 'ACCOUNT_DELETE_FAILED');
    }

    // Las imágenes no desaparecen automáticamente al borrar PostgreSQL.
    for (const name of IMAGE_COLLECTIONS) {
      mongoModified = true;
      const collection = mongo.collection(name);
      await collection.deleteMany({ usuarioIdPg: userId });
      if (await collection.countDocuments({ usuarioIdPg: userId }) !== 0) {
        throw new Error('MONGO_IMAGES_NOT_REMOVED');
      }
    }

    await client.query('COMMIT');
    committed = true;
    transactionStarted = false;
    return { deleted: true };
  } catch (error) {
    let rollbackFailed = false;
    if (transactionStarted && !committed) {
      try {
        await client.query('ROLLBACK');
      } catch (_) {
        rollbackFailed = true;
      }
    }

    // Si hubo un problema, recuperar los archivos Mongo que se quitaron.
    // No prometer reversión completa si ocurrió una falla de conexión.
    let restoreProblems = [];
    if (mongoModified && mongo) {
      restoreProblems = await restoreImages(mongo, userId, backups);
    }
    if (restoreProblems.length || rollbackFailed) {
      throw userError(
        'No se pudo confirmar la operación. Revisa el estado de las bases de datos antes de reintentar.',
        503,
        'ACCOUNT_DELETION_STATE_UNCERTAIN'
      );
    }
    if (error.statusCode) throw error;
    throw userError(
      'No fue posible eliminar la cuenta. Intenta nuevamente.',
      503,
      'ACCOUNT_DELETION_FAILED'
    );
  } finally {
    client.release();
  }
}

module.exports = { deleteOwnAccount };
