const { ObjectId } = require('mongodb');
const { getMongoDb } = require('../../config/mongo_db');

const { generarMiniatura } = require('../pets/pet-image-optimizer');

const COLLECTION_NAME = 'ImagenAvistamiento';

async function getCollection() {
  const db = await getMongoDb();
  return db.collection(COLLECTION_NAME);
}


async function saveSightingImage({ sightingId, userId, file }) {
  const collection = await getCollection();
  const id = new ObjectId();
  const now = new Date();

  // Generar una versión pequeña de la fotografía.
  // Si falla la compresión, conservar el original.
  let miniatura = null;

  try {
    miniatura = await generarMiniatura(file.buffer);
  } catch (error) {
    console.warn(
      'No se pudo optimizar la foto del avistamiento:',
      error.message
    );
  }

  const document = {
    _id: id,
    avistamientoIdPg: Number(sightingId),
    usuarioIdPg: Number(userId),
    nombreArchivo: file.originalname,
    mimeType: file.mimetype,
    tamanoBytes: file.size,
    storageRef: id.toHexString(),

    // Original: se conserva para reconocimiento.
    imagen: file.buffer,

    // Miniatura para las interfaces.
    miniatura,
    miniaturaMimeType: miniatura ? 'image/webp' : null,
    miniaturaTamanoBytes: miniatura
      ? miniatura.length
      : null,

    createdAt: now,
    updatedAt: now,
  };

  await collection.insertOne(document);

  return {
    ...document,
    urlPreview: `/api/sightings/images/${document.storageRef}`,
  };
}


async function deleteSightingImage(imageId) {
  if (!imageId || !ObjectId.isValid(imageId)) return;
  const collection = await getCollection();
  await collection.deleteOne({ _id: new ObjectId(imageId) });
}

async function findPublicSightingImage(imageId) {
  if (!ObjectId.isValid(imageId)) return null;
  const collection = await getCollection();
  return collection.findOne({ _id: new ObjectId(imageId) });
}

module.exports = {
  deleteSightingImage,
  findPublicSightingImage,
  saveSightingImage,
};
