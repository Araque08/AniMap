const { ObjectId, Binary } = require('mongodb');
const postgres = require('../../config/postgres_db');
function createRecognitionRepository({ pool = postgres.pool,
  mongo = () => require('../../config/mongo_db').getMongoDb() } = {}) {
  async function activePhotos() {
    const result = await pool.query({ text: `SELECT r.id AS "reportId", m.id AS "petId",
      r.fk_usuario AS "ownerId", f.storage_ref AS "photoId", m.nombre, m.color,
      e.nombre AS especie, z.nombre AS raza
      FROM reporte r JOIN mascota m ON m.id = r.fk_mascota AND m.fk_usuario = r.fk_usuario
      JOIN foto_mascota f ON f.fk_mascota = m.id
      JOIN especie e ON e.id = m.fk_especie LEFT JOIN raza z ON z.id = m.fk_raza
      WHERE r.estado = 'ACTIVO' AND m.estado = 'PERDIDA' ORDER BY r.id, f.id`,
      values: [], query_timeout: 5000 });
    return result.rows;
  }
  async function photoBytes(photo) {
    if (!ObjectId.isValid(photo.photoId)) return null;
    const db = await mongo();
    const image = await db.collection('ImagenMascota').findOne({
      _id: new ObjectId(photo.photoId), mascotaIdPg: photo.petId,
      usuarioIdPg: photo.ownerId, estado: 'ACTIVA',
    }, { maxTimeMS: 5000, projection: { imagen: 1, buffer: 1 } });
    const content = image?.imagen ?? image?.buffer;
    if (Buffer.isBuffer(content)) return content;
    if (content instanceof Binary) return Buffer.from(content.value());
    return null;
  }
  return { activePhotos, photoBytes };
}
module.exports = { createRecognitionRepository };
