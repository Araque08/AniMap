const db = require('../../config/postgres_db');
const imageRepository = require('./profile.images.repository');

function createHttpError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

async function queryProfile(queryable, userId) {
  const result = await queryable.query(
    `
      SELECT
        u.id,
        u.nombre,
        u.email,
        u.telefono,
        p.foto_url,
        p.notificaciones_activas
      FROM usuario u
      INNER JOIN perfil p ON p.fk_usuario = u.id
      WHERE u.id = $1
      LIMIT 1
    `,
    [userId]
  );

  if (result.rowCount === 0) {
    throw createHttpError('Perfil no encontrado', 404);
  }

  return result.rows[0];
}

async function getProfile(userId) {
  return queryProfile(db, userId);
}

async function updateProfile(userId, data) {
  const result = await db.query(
    `
      UPDATE usuario
      SET
        nombre = COALESCE($2, nombre),
        telefono = COALESCE($3, telefono)
      WHERE id = $1
      RETURNING id
    `,
    [userId, data.nombre ?? null, data.telefono ?? null]
  );

  if (result.rowCount === 0) {
    throw createHttpError('Perfil no encontrado', 404);
  }

  return getProfile(userId);
}

async function updateProfilePhoto(userId, file) {
  const client = await db.pool.connect();
  let newImage = null;
  let previousImage = null;
  try {
    await client.query('BEGIN');
    const profileResult = await client.query(
      `SELECT foto_storage_ref
       FROM perfil
       WHERE fk_usuario = $1
       FOR UPDATE`,
      [userId]
    );
    if (profileResult.rowCount === 0) {
      throw createHttpError('Perfil no encontrado', 404);
    }

    newImage = await imageRepository.saveProfileImage({ userId, file });
    const storageRef = newImage._id.toHexString();
    const photoUrl = `/api/profile/photo/${storageRef}`;

    await client.query(
      `UPDATE perfil
       SET foto_url = $2, foto_storage_ref = $3
       WHERE fk_usuario = $1`,
      [userId, photoUrl, storageRef]
    );

    previousImage = await imageRepository.deleteProfileImage({
      userId,
      imageId: profileResult.rows[0].foto_storage_ref,
    });

    const profile = await queryProfile(client, userId);
    await client.query('COMMIT');
    return profile;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    if (newImage) {
      await imageRepository.deleteProfileImage({
        userId,
        imageId: newImage._id,
      }).catch(() => undefined);
    }
    await imageRepository.restoreProfileImage(previousImage).catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

async function getProfilePhoto(userId, imageId) {
  const result = await db.query(
    `SELECT foto_storage_ref
     FROM perfil
     WHERE fk_usuario = $1 AND foto_storage_ref = $2
     LIMIT 1`,
    [userId, imageId]
  );
  if (result.rowCount === 0) {
    throw createHttpError('Foto de perfil no encontrada', 404);
  }

  const image = await imageRepository.findProfileImage({ userId, imageId });
  if (!image) throw createHttpError('Foto de perfil no encontrada', 404);
  const content = image.imagen || image.buffer;
  const buffer = Buffer.isBuffer(content)
    ? content
    : content?.buffer
      ? Buffer.from(content.buffer)
      : null;
  if (!buffer) throw createHttpError('Foto de perfil no encontrada', 404);
  return { buffer, mimeType: image.mimeType || 'application/octet-stream' };
}

module.exports = {
  getProfilePhoto,
  getProfile,
  updateProfile,
  updateProfilePhoto,
};
