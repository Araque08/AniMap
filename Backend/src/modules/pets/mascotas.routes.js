const express = require('express');
const multer = require('multer');
const postgres = require('../../config/postgres_db');
const authMiddleware = require('../../middleware/auth.middleware');
const {
  eliminarImagenesMascotaMongoPorIds,
  guardarImagenesMascota,
} = require('./pets.images.repository');

const router = express.Router();
const MIN_IMAGES = 15;
const MAX_IMAGES_PER_REQUEST = 30;
const MAX_IMAGE_SIZE = 5 * 1024 * 1024;

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_IMAGE_SIZE, files: MAX_IMAGES_PER_REQUEST },
});

function uploadImages(req, res, next) {
  upload.array('imagenes', MAX_IMAGES_PER_REQUEST)(req, res, (error) => {
    if (error) {
      return res.status(400).json({
        ok: false,
        message: 'Máximo 30 imágenes de hasta 5 MB cada una',
      });
    }
    return next();
  });
}

function isValidImage(file) {
  if (!file?.buffer?.length) return false;
  const buffer = file.buffer;
  if (file.mimetype === 'image/jpeg') {
    return buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  }
  if (file.mimetype === 'image/png') {
    return buffer.length >= 8 && buffer.subarray(0, 8).equals(
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    );
  }
  if (file.mimetype === 'image/webp') {
    return buffer.length >= 12 &&
      buffer.toString('ascii', 0, 4) === 'RIFF' &&
      buffer.toString('ascii', 8, 12) === 'WEBP';
  }
  return false;
}

router.post('/', authMiddleware, uploadImages, async (req, res) => {
  const usuarioId = req.auth.userId;
  const files = req.files || [];
  const especieId = Number(req.body.fk_especie);
  const razaId = req.body.fk_raza ? Number(req.body.fk_raza) : null;
  const edadAprox = req.body.edad_aprox === undefined || req.body.edad_aprox === ''
    ? null
    : Number(req.body.edad_aprox);
  const fotoPrincipalIndex = Number(req.body.foto_principal_index);
  const nombre = req.body.nombre?.trim();
  const color = req.body.color?.trim();
  const unidadEdad = ['MESES', 'ANIOS'].includes(req.body.unidad_edad)
    ? req.body.unidad_edad
    : null;
  const sexo = ['MACHO', 'HEMBRA', 'NO_DEFINIDO'].includes(req.body.sexo)
    ? req.body.sexo
    : 'NO_DEFINIDO';

  if (!Number.isInteger(especieId) || especieId <= 0 || !nombre || !color) {
    return res.status(400).json({
      ok: false,
      message: 'Nombre, especie y color son obligatorios',
    });
  }
  if (razaId !== null && (!Number.isInteger(razaId) || razaId <= 0)) {
    return res.status(400).json({ ok: false, message: 'La raza no es válida' });
  }
  if (edadAprox !== null && (!Number.isInteger(edadAprox) || edadAprox < 0)) {
    return res.status(400).json({ ok: false, message: 'La edad no es válida' });
  }
  if (files.length < MIN_IMAGES) {
    return res.status(400).json({
      ok: false,
      message: `Debes cargar mínimo ${MIN_IMAGES} imágenes`,
    });
  }
  if (!files.every(isValidImage)) {
    return res.status(400).json({
      ok: false,
      message: 'Solo se permiten imágenes JPEG, PNG o WEBP válidas de hasta 5 MB',
    });
  }
  if (!Number.isInteger(fotoPrincipalIndex) ||
      fotoPrincipalIndex < 0 ||
      fotoPrincipalIndex >= files.length) {
    return res.status(400).json({
      ok: false,
      message: 'Debes seleccionar una foto principal válida',
    });
  }

  const client = await postgres.pool.connect();
  let imagenesMongo = [];
  try {
    await client.query('BEGIN');

    if (razaId !== null) {
      const raza = await client.query(
        'SELECT id FROM raza WHERE id = $1 AND fk_especie = $2',
        [razaId, especieId]
      );
      if (raza.rowCount === 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          ok: false,
          message: 'La raza no corresponde a la especie seleccionada',
        });
      }
    }

    const mascotaResult = await client.query(
      `INSERT INTO mascota (
        fk_usuario, fk_especie, fk_raza, nombre, color,
        edad_aprox, unidad_edad, sexo, observaciones
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
      RETURNING id`,
      [
        usuarioId,
        especieId,
        razaId,
        nombre,
        color,
        edadAprox,
        unidadEdad,
        sexo,
        req.body.observaciones?.trim() || null,
      ]
    );
    const mascotaId = mascotaResult.rows[0].id;

    imagenesMongo = await guardarImagenesMascota({
      mascotaIdPg: mascotaId,
      usuarioIdPg: usuarioId,
      files,
      fotoPrincipalIndex,
    });

    for (const imagen of imagenesMongo) {
      await client.query(
        `INSERT INTO foto_mascota (
          fk_mascota, storage_ref, url_preview, es_principal
        ) VALUES ($1, $2, $3, $4)`,
        [mascotaId, imagen.storageRef, imagen.urlPreview, imagen.esPrincipal]
      );
    }

    await client.query('COMMIT');
    return res.status(201).json({
      ok: true,
      message: 'Mascota registrada exitosamente',
      mascotaId,
      imagenesGuardadas: imagenesMongo.length,
    });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    await eliminarImagenesMascotaMongoPorIds(
      imagenesMongo.map((imagen) => imagen.id)
    ).catch((cleanupError) => {
      console.error('No se pudo compensar MongoDB:', cleanupError.message);
    });
    console.error('Error registrando mascota:', error);
    return res.status(500).json({
      ok: false,
      message: 'Error interno registrando la mascota',
    });
  } finally {
    client.release();
  }
});

module.exports = router;
