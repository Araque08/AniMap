const { ObjectId } = require('mongodb');
const { getMongoDb } = require('../../config/mongo_db');

const COLLECTION_NAME = 'ImagenMascota';

async function getCollection() {
  const db = await getMongoDb();
  return db.collection(COLLECTION_NAME);
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

async function inactivarImagenesMascotaMongo({ mascotaId, usuarioId }) {
  const collection = await getCollection();
  const filter = {
    mascotaIdPg: Number(mascotaId),
    usuarioIdPg: Number(usuarioId),
    estado: { $ne: 'INACTIVA' },
  };
  const documentos = await collection.find(filter).project({ _id: 1 }).toArray();
  const result = await collection.updateMany(filter, {
    $set: { estado: 'INACTIVA', updatedAt: new Date() },
  });
  return {
    matchedCount: result.matchedCount,
    modifiedCount: result.modifiedCount,
    ids: documentos.map((item) => item._id),
  };
}

async function reactivarImagenesMascotaMongo(ids) {
  if (!ids.length) return;
  const collection = await getCollection();
  await collection.updateMany(
    { _id: { $in: ids } },
    { $set: { estado: 'ACTIVA', updatedAt: new Date() } }
  );
}

module.exports = {
  eliminarImagenMascotaMongo,
  eliminarImagenesMascotaMongoPorIds,
  establecerPrincipalMongo,
  guardarImagenesMascota,
  inactivarImagenesMascotaMongo,
  reactivarImagenesMascotaMongo,
  restaurarImagenMascotaMongo,
  restaurarPrincipalesMongo,
};
