const { ObjectId } = require('mongodb');
const { getMongoDb } = require('../../config/mongo_db');

const COLLECTION_NAME = 'ImagenPerfil';

async function getCollection() {
  const db = await getMongoDb();
  return db.collection(COLLECTION_NAME);
}

async function saveProfileImage({ userId, file }) {
  const collection = await getCollection();
  const id = new ObjectId();
  const now = new Date();
  const document = {
    _id: id,
    usuarioIdPg: Number(userId),
    nombreArchivo: file.originalname,
    mimeType: file.mimetype,
    tamanoBytes: file.size,
    imagen: file.buffer,
    createdAt: now,
    updatedAt: now,
  };
  await collection.insertOne(document);
  return document;
}

async function findProfileImage({ userId, imageId }) {
  if (!ObjectId.isValid(imageId)) return null;
  const collection = await getCollection();
  return collection.findOne({
    _id: new ObjectId(imageId),
    usuarioIdPg: Number(userId),
  });
}

async function deleteProfileImage({ userId, imageId }) {
  if (!imageId || !ObjectId.isValid(imageId)) return null;
  const collection = await getCollection();
  const filter = {
    _id: new ObjectId(imageId),
    usuarioIdPg: Number(userId),
  };
  const document = await collection.findOne(filter);
  if (document) await collection.deleteOne(filter);
  return document;
}

async function restoreProfileImage(document) {
  if (!document) return;
  const collection = await getCollection();
  await collection.replaceOne({ _id: document._id }, document, { upsert: true });
}

module.exports = {
  deleteProfileImage,
  findProfileImage,
  restoreProfileImage,
  saveProfileImage,
};
