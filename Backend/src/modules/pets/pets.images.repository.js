const { getMongoDb } = require('../../config/mongo_db');

async function guardarImagenesMascota({
  mascotaIdPg,
  usuarioIdPg,
  files,
  fotoPrincipalIndex = 0,
}) {
  const db = await getMongoDb();

  const collection = db.collection('ImagenMascota');

  const documentos = files.map((file, index) => ({
    mascotaIdPg: Number(mascotaIdPg),
    usuarioIdPg: Number(usuarioIdPg),
    nombreArchivo: file.originalname,
    mimeType: file.mimetype,
    extension: file.originalname.split('.').pop(),
    tamanoBytes: file.size,
    storageRef: null,
    buffer: file.buffer,
    esPrincipal: index === fotoPrincipalIndex,
    estado: 'ACTIVA',
    checksum: null,
    etiquetas: [],
    metadata: {},
    createdAt: new Date(),
    updatedAt: new Date(),
  }));

  await collection.insertMany(documentos);

  return documentos.length;
}

module.exports = {
  guardarImagenesMascota,
};