const { ObjectId, BSON } = require('mongodb');
const { randomUUID, createHash } = require('node:crypto');
const { getMongoDb } = require('../../config/mongo_db');

const COLLECTION_NAME = 'ImagenMascota';
const RECOVERY_COLLECTION = 'PetPhotoDeletionRecovery';
const DURABLE_WRITE = { writeConcern: { w: 'majority' } };

function recoveryError(code, operationId) {
  const error = new Error(code);
  error.code = code;
  error.operationId = operationId;
  return error;
}

function documentHash(document) {
  return createHash('sha256').update(BSON.serialize(document)).digest('hex');
}

async function recoveryCollection() {
  const db = await getMongoDb();
  return db.collection(RECOVERY_COLLECTION, {
    readConcern: { level: 'majority' }, writeConcern: { w: 'majority' },
  });
}

function ownerFilter(operation) {
  return { mascotaIdPg: operation.mascotaId, usuarioIdPg: operation.usuarioId };
}

function matchesManifest(documents, operation) {
  const expected = new Map(operation.images.map(image => [String(image.id), image.hash]));
  const actualIds = new Set(documents.map(document => String(document._id)));
  return documents.length === expected.size && actualIds.size === expected.size && documents.every(document =>
    expected.get(String(document._id)) === documentHash(document));
}

async function readBackup(operation) {
  const journal = await recoveryCollection();
  const entries = await journal.find({ operationId: operation._id, kind: 'photo' }).toArray();
  const originals = entries.map(entry => entry.original);
  if (!matchesManifest(originals, operation) || originals.some(document =>
    document.mascotaIdPg !== operation.mascotaId || document.usuarioIdPg !== operation.usuarioId)) {
    throw recoveryError('PET_PHOTO_BACKUP_INCOMPLETE', operation._id);
  }
  return originals;
}

async function getPetPhotoRecovery(operationId) {
  const journal = await recoveryCollection();
  return journal.findOne({ _id: operationId, kind: 'operation' });
}

async function prepareDeletionBackup({ mascotaId, usuarioId, estadoOriginal }) {
  const journal = await recoveryCollection();
  const existing = await journal.findOne({ kind: 'operation', mascotaId, usuarioId });
  if (existing) throw recoveryError('PET_PHOTO_RECOVERY_PENDING', existing._id);
  const collection = await getCollection();
  const originals = await collection.find({ mascotaIdPg: mascotaId, usuarioIdPg: usuarioId }).toArray();
  const operation = {
    _id: randomUUID(), kind: 'operation', phase: 'PREPARING', mascotaId, usuarioId,
    estadoOriginal, createdAt: new Date(),
    bytes: originals.reduce((total, document) => total + BSON.calculateObjectSize(document), 0),
    images: originals.map(document => ({ id: document._id, hash: documentHash(document) })),
  };
  try {
    await journal.insertOne(operation);
    if (originals.length) {
      await journal.insertMany(originals.map(original => ({
        _id: `${operation._id}:${original._id}`, kind: 'photo', operationId: operation._id, original,
      })));
    }
    // Read back every BSON document, including image bytes, before destructive writes.
    await readBackup(operation);
    const updated = await journal.updateOne({ _id: operation._id, phase: 'PREPARING' }, {
      $set: { phase: 'READY' },
    });
    if (updated.matchedCount !== 1) throw recoveryError('PET_PHOTO_BACKUP_INCOMPLETE', operation._id);
    const confirmed = await getPetPhotoRecovery(operation._id);
    if (confirmed?.phase !== 'READY') throw recoveryError('PET_PHOTO_BACKUP_INCOMPLETE', operation._id);
    return confirmed;
  } catch (_) {
    throw recoveryError('PET_PHOTO_BACKUP_FAILED', operation._id);
  }
}

async function cleanupPetPhotoRecovery(operation) {
  const journal = await recoveryCollection();
  // Delete the header last: a crash/partial cleanup keeps a resumable operation.
  await journal.deleteMany({ operationId: operation._id, kind: 'photo' });
  await journal.deleteOne({ _id: operation._id, kind: 'operation' });
}

async function resolvePetPhotoRecovery(operation, outcome) {
  const journal = await recoveryCollection();
  const result = await journal.updateOne({ _id: operation._id, kind: 'operation' }, {
    $set: { phase: 'RESOLVED', outcome },
  });
  if (result.matchedCount !== 1) throw recoveryError('PET_PHOTO_STATE_UNCONFIRMED', operation._id);
  await cleanupPetPhotoRecovery(operation);
}

async function reconcilePetPhotos(operation, estado) {
  if (operation.phase === 'RESOLVED') return operation.outcome;
  const collection = await getCollection();
  const filter = ownerFilter(operation);
  const current = await collection.find(filter).toArray();
  if (estado === operation.estadoOriginal) {
    if (operation.phase === 'PREPARING') {
      // No deletion can start in PREPARING. Incomplete backup writes are disposable
      // only after verifying every original still exists in the live collection.
      if (!matchesManifest(current, operation)) throw recoveryError('PET_PHOTO_RECOVERY_CONFLICT', operation._id);
      return 'RESTORED';
    }
    const originals = await readBackup(operation);
    const expected = new Map(operation.images.map(image => [String(image.id), image.hash]));
    if (current.some(document => expected.get(String(document._id)) !== documentHash(document))) {
      throw recoveryError('PET_PHOTO_RECOVERY_CONFLICT', operation._id);
    }
    for (const original of originals) {
      try {
        await collection.updateOne({ _id: original._id, ...filter }, {
          $setOnInsert: original,
        }, { upsert: true, ...DURABLE_WRITE });
      } catch (_) { /* Verify actual contents below; continue restoring other photos. */ }
    }
    if (!matchesManifest(await collection.find(filter).toArray(), operation)) {
      throw recoveryError('PET_PHOTO_RESTORE_INCOMPLETE', operation._id);
    }
    return 'RESTORED';
  }
  if (estado !== 'INACTIVA' || operation.phase !== 'READY') {
    throw recoveryError('PET_PHOTO_RECOVERY_CONFLICT', operation._id);
  }
  await readBackup(operation);
  const expected = new Map(operation.images.map(image => [String(image.id), image.hash]));
  if (current.some(document => expected.get(String(document._id)) !== documentHash(document))) {
    throw recoveryError('PET_PHOTO_RECOVERY_CONFLICT', operation._id);
  }
  // PostgreSQL committed: finish only the exact original IDs, never a broad delete.
  await collection.deleteMany({ ...filter, _id: { $in: operation.images.map(image => image.id) } }, DURABLE_WRITE);
  if (await collection.countDocuments(filter) !== 0) {
    throw recoveryError('PET_PHOTO_DELETE_INCOMPLETE', operation._id);
  }
  return 'DELETED';
}

async function getCollection() {
  const db = await getMongoDb();
  return db.collection(COLLECTION_NAME);
}

async function findActivePetImages({ mascotaId, usuarioId, imageIds }) {
  if (!imageIds.length) return [];
  const collection = await getCollection();
  const objectIds = imageIds.map((id) =>
    id instanceof ObjectId ? id : new ObjectId(id)
  );
  return collection.find({
    _id: { $in: objectIds },
    mascotaIdPg: Number(mascotaId),
    usuarioIdPg: Number(usuarioId),
    estado: 'ACTIVA',
  }).toArray();
}

async function guardarImagenesMascota({
  mascotaIdPg,
  usuarioIdPg,
  files,
  fotoPrincipalIndex = null,
}) {
  const collection = await getCollection();
  const ids = files.map(() => new ObjectId());
  const now = new Date();
  const documentos = files.map((file, index) => ({
    _id: ids[index],
    mascotaIdPg: Number(mascotaIdPg),
    usuarioIdPg: Number(usuarioIdPg),
    nombreArchivo: file.originalname,
    mimeType: file.mimetype,
    extension: file.originalname.split('.').pop()?.toLowerCase() || null,
    tamanoBytes: file.size,
    storageRef: ids[index].toHexString(),
    imagen: file.buffer,
    esPrincipal: fotoPrincipalIndex === index,
    estado: 'ACTIVA',
    checksum: null,
    etiquetas: [],
    metadata: {},
    createdAt: now,
    updatedAt: now,
  }));

  try {
    await collection.insertMany(documentos);
  } catch (error) {
    await collection.deleteMany({ _id: { $in: ids } }).catch(() => undefined);
    throw error;
  }

  return documentos.map((documento) => ({
    id: documento._id,
    storageRef: documento.storageRef,
    urlPreview: `/api/pets/images/${documento._id}`,
    esPrincipal: documento.esPrincipal,
  }));
}

async function eliminarImagenesMascotaMongoPorIds(ids) {
  if (!ids.length) return;
  const collection = await getCollection();
  const objectIds = ids.map((id) =>
    id instanceof ObjectId ? id : new ObjectId(id)
  );
  await collection.deleteMany({ _id: { $in: objectIds } });
}

async function restaurarPrincipalesMongo({ mascotaId, usuarioId, principalIds }) {
  const collection = await getCollection();
  const filterBase = {
    mascotaIdPg: Number(mascotaId),
    usuarioIdPg: Number(usuarioId),
    estado: 'ACTIVA',
  };
  await collection.updateMany(filterBase, {
    $set: { esPrincipal: false, updatedAt: new Date() },
  });
  if (principalIds.length) {
    await collection.updateMany(
      { ...filterBase, _id: { $in: principalIds } },
      { $set: { esPrincipal: true, updatedAt: new Date() } }
    );
  }
}

async function establecerPrincipalMongo({ mascotaId, usuarioId, imageId }) {
  const collection = await getCollection();
  const objectId = imageId instanceof ObjectId ? imageId : new ObjectId(imageId);
  const filterBase = {
    mascotaIdPg: Number(mascotaId),
    usuarioIdPg: Number(usuarioId),
    estado: 'ACTIVA',
  };
  const anteriores = await collection
    .find({ ...filterBase, esPrincipal: true })
    .project({ _id: 1 })
    .toArray();

  await collection.updateMany(filterBase, {
    $set: { esPrincipal: false, updatedAt: new Date() },
  });
  const result = await collection.updateOne(
    { ...filterBase, _id: objectId },
    { $set: { esPrincipal: true, updatedAt: new Date() } }
  );
  if (result.matchedCount !== 1) {
    await restaurarPrincipalesMongo({
      mascotaId,
      usuarioId,
      principalIds: anteriores.map((item) => item._id),
    });
    throw new Error('La imagen no existe o no pertenece a la mascota');
  }
  return anteriores.map((item) => item._id);
}

async function eliminarImagenMascotaMongo({ mascotaId, usuarioId, imageId }) {
  const collection = await getCollection();
  const objectId = imageId instanceof ObjectId ? imageId : new ObjectId(imageId);
  const filter = {
    _id: objectId,
    mascotaIdPg: Number(mascotaId),
    usuarioIdPg: Number(usuarioId),
    estado: 'ACTIVA',
  };
  const documento = await collection.findOne(filter);
  if (!documento) throw new Error('La imagen no existe o no pertenece a la mascota');
  const result = await collection.deleteOne(filter);
  if (result.deletedCount !== 1) throw new Error('No fue posible eliminar la imagen');
  return documento;
}

async function restaurarImagenMascotaMongo(documento) {
  const collection = await getCollection();
  await collection.replaceOne({ _id: documento._id }, documento, { upsert: true });
}

async function eliminarImagenesMascotaMongo({ mascotaId, usuarioId, estadoOriginal }) {
  let operation;
  try {
    operation = await prepareDeletionBackup({ mascotaId, usuarioId, estadoOriginal });
    const collection = await getCollection();
    const filter = ownerFilter(operation);
    const result = await collection.deleteMany({ ...filter,
      _id: { $in: operation.images.map(image => image.id) },
    }, DURABLE_WRITE);
    if (await collection.countDocuments(filter) !== 0) {
      throw recoveryError('PET_PHOTO_DELETE_INCOMPLETE', operation._id);
    }
    return { deletedCount: result.deletedCount, operationId: operation._id };
  } catch (error) {
    throw recoveryError('PET_PHOTO_DELETE_FAILED', operation?._id || error.operationId);
  }
}

module.exports = {
  eliminarImagenMascotaMongo,
  eliminarImagenesMascotaMongoPorIds,
  establecerPrincipalMongo,
  findActivePetImages,
  guardarImagenesMascota,
  eliminarImagenesMascotaMongo,
  restaurarImagenMascotaMongo,
  restaurarPrincipalesMongo,
  getPetPhotoRecovery,
  reconcilePetPhotos,
  resolvePetPhotoRecovery,
  cleanupPetPhotoRecovery,
};
