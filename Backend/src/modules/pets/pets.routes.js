const express = require('express');
const multer = require('multer');
const { ObjectId } = require('mongodb');
const postgres = require('../../config/postgres_db');
const { getMongoDb } = require('../../config/mongo_db');
const authMiddleware = require('../../middleware/auth.middleware');
const {
  eliminarImagenMascotaMongo,
  eliminarImagenesMascotaMongoPorIds,
  establecerPrincipalMongo,
  guardarImagenesMascota,
  inactivarImagenesMascotaMongo,
  reactivarImagenesMascotaMongo,
  restaurarImagenMascotaMongo,
  restaurarPrincipalesMongo,
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

function validPositiveInteger(value) {
  return Number.isInteger(value) && value > 0;
}

async function petBelongsToUser(queryable, mascotaId, usuarioId, lock = false) {
  const result = await queryable.query(
    `SELECT id, estado FROM mascota
     WHERE id = $1 AND fk_usuario = $2${lock ? ' FOR UPDATE' : ''}`,
    [mascotaId, usuarioId]
  );
  return result.rows[0] || null;
}

// =====================================================
// GET /api/pets/especies
// Consulta las especies disponibles para mascotas.
// PostgreSQL: consulta especies.
// MongoDB no se toca aquí.
// =====================================================
router.use(authMiddleware);

router.get('/especies', async (req, res) => {
  try {
    const result = await postgres.query(`
      SELECT id, nombre
      FROM especie
      ORDER BY nombre ASC
    `);

    return res.json({
      ok: true,
      especies: result.rows,
    });
  } catch (error) {
    console.error('Error obteniendo especies:', error);
    return res.status(500).json({
      ok: false,
      message: 'Error obteniendo especies',
    });
  }
});

// =====================================================
// GET /api/pets/razas
// Consulta las razas disponibles para mascotas.
// PostgreSQL: consulta razas.
// MongoDB no se toca aquí.
// =====================================================
router.get('/razas/:especieId', async (req, res) => {
  try {
    const { especieId } = req.params;

    const result = await postgres.query(
      `
      SELECT id, nombre, fk_especie
      FROM raza
      WHERE fk_especie = $1
      ORDER BY nombre ASC
      `,
      [especieId]
    );

    return res.json({
      ok: true,
      razas: result.rows,
    });
  } catch (error) {
    console.error('Error obteniendo razas:', error);
    return res.status(500).json({
      ok: false,
      message: 'Error obteniendo razas',
    });
  }
});

// =====================================================
// GET /api/pets/sexos
// Consulta los sexos disponibles para mascotas.
// PostgreSQL: consulta sexos.
// MongoDB no se toca aquí.
// =====================================================
router.get('/sexos', (req, res) => {
  return res.json({
    ok: true,
    sexos: [
      { id: 'MACHO', nombre: 'Macho' },
      { id: 'HEMBRA', nombre: 'Hembra' },
      { id: 'NO_DEFINIDO', nombre: 'No definido' },
    ],
  });
});

// =====================================================
// GET /api/pets/my
// Lista las mascotas del usuario.
// PostgreSQL: datos de mascota, especie, raza y referencia de imagen principal.
// =====================================================
router.get('/my', async (req, res) => {
  try {
    const result = await postgres.query(
      `SELECT
        m.id, m.fk_usuario, m.fk_especie, m.fk_raza, m.nombre, m.color,
        m.edad_aprox, m.unidad_edad, m.sexo, m.estado, m.observaciones,
        m.fecha_registro, e.nombre AS especie, r.nombre AS raza,
        fp.storage_ref AS foto_storage_ref, fp.url_preview AS foto_url_preview
      FROM mascota m
      INNER JOIN especie e ON e.id = m.fk_especie
      LEFT JOIN raza r ON r.id = m.fk_raza
      LEFT JOIN LATERAL (
        SELECT storage_ref, url_preview
        FROM foto_mascota
        WHERE fk_mascota = m.id AND es_principal = TRUE
        LIMIT 1
      ) fp ON TRUE
      WHERE m.fk_usuario = $1 AND m.estado <> 'INACTIVA'
      ORDER BY m.fecha_registro DESC`,
      [req.auth.userId]
    );

    const mascotas = result.rows.map((mascota) => ({
      ...mascota,
      fotoPrincipal: mascota.foto_storage_ref
            ? {
            id: mascota.foto_storage_ref,
            url: mascota.foto_url_preview || `/api/pets/images/${mascota.foto_storage_ref}`,
              }
            : null,
      foto_storage_ref: undefined,
      foto_url_preview: undefined,
    }));
    return res.status(200).json({ ok: true, total: mascotas.length, mascotas });
  } catch (error) {
    console.error('Error consultando mascotas:', error);
    return res.status(500).json({ ok: false, message: 'Error consultando las mascotas' });
  }
});

// =====================================================
// GET /api/pets/images/:imageId
// Retorna una imagen guardada en MongoDB.
// =====================================================
router.get('/images/:imageId', async (req, res) => {
  if (!ObjectId.isValid(req.params.imageId)) {
    return res.status(400).json({ ok: false, message: 'ID de imagen inválido' });
    }
  try {
    const db = await getMongoDb();
    const imagen = await db.collection('ImagenMascota').findOne({
      _id: new ObjectId(req.params.imageId),
      usuarioIdPg: req.auth.userId,
      estado: 'ACTIVA',
      });
    const contenido = imagen?.imagen || imagen?.buffer;
    if (!contenido) {
      return res.status(404).json({ ok: false, message: 'Imagen no encontrada' });
    }
    res.set('Content-Type', imagen.mimeType || 'application/octet-stream');
    res.set('Cache-Control', 'private, max-age=86400');
    return res.send(contenido);
  } catch (error) {
    console.error('Error consultando imagen:', error);
    return res.status(500).json({ ok: false, message: 'Error consultando la imagen' });
  }
});

// =====================================================
// GET /api/pets/:id/images
// Lista las referencias de las imágenes de una mascota.
// No devuelve el contenido binario, solo las URLs para mostrarlas.
// =====================================================
router.get('/:id/images', async (req, res) => {
    const mascotaId = Number(req.params.id);
  if (!validPositiveInteger(mascotaId)) {
    return res.status(400).json({ ok: false, message: 'ID de mascota inválido' });
    }
  try {
    const mascota = await petBelongsToUser(postgres, mascotaId, req.auth.userId);
    if (!mascota || mascota.estado === 'INACTIVA') {
      return res.status(404).json({ ok: false, message: 'Mascota no encontrada' });
    }
    const result = await postgres.query(
      `SELECT id, storage_ref, url_preview, es_principal, fecha
       FROM foto_mascota WHERE fk_mascota = $1
       ORDER BY es_principal DESC, fecha ASC`,
      [mascotaId]
    );
    const imagenes = result.rows.map((imagen) => ({
      id: imagen.storage_ref,
      metadataId: imagen.id,
      storageRef: imagen.storage_ref,
      url: imagen.url_preview || `/api/pets/images/${imagen.storage_ref}`,
      esPrincipal: imagen.es_principal,
      fecha: imagen.fecha,
    }));
    return res.status(200).json({ ok: true, total: imagenes.length, imagenes });
  } catch (error) {
    console.error('Error consultando imágenes:', error);
    return res.status(500).json({ ok: false, message: 'Error consultando las imágenes' });
  }
});

// =====================================================
// POST /api/pets/:id/images
// Agrega nuevas fotos a una mascota existente.
// =====================================================
router.post('/:id/images', uploadImages, async (req, res) => {
    const mascotaId = Number(req.params.id);
  const files = req.files || [];
  const marcarComoPrincipal = req.body.marcar_como_principal === 'true' ||
    req.body.marcar_como_principal === true;
  const principalIndex = marcarComoPrincipal ? Number(req.body.foto_principal_index) : null;

  if (!validPositiveInteger(mascotaId)) {
    return res.status(400).json({ ok: false, message: 'ID de mascota inválido' });
    }
  if (!files.length || !files.every(isValidImage)) {
      return res.status(400).json({
        ok: false,
      message: 'Debes enviar imágenes JPEG, PNG o WEBP válidas de hasta 5 MB',
      });
    }
  if (marcarComoPrincipal &&
      (!Number.isInteger(principalIndex) || principalIndex < 0 || principalIndex >= files.length)) {
    return res.status(400).json({ ok: false, message: 'Índice de foto principal inválido' });
  }

  const client = await postgres.pool.connect();
  let nuevasImagenes = [];
  let principalesMongoAnteriores = null;
  try {
    await client.query('BEGIN');
    const mascota = await petBelongsToUser(client, mascotaId, req.auth.userId, true);
    if (!mascota || mascota.estado === 'INACTIVA') {
      await client.query('ROLLBACK');
      return res.status(404).json({ ok: false, message: 'Mascota no encontrada' });
    }
    const principales = await client.query(
      'SELECT storage_ref FROM foto_mascota WHERE fk_mascota = $1 AND es_principal = TRUE',
      [mascotaId]
    );
    if (!marcarComoPrincipal && principales.rowCount !== 1) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        ok: false,
        message: 'Debes seleccionar una foto principal',
      });
    }

    nuevasImagenes = await guardarImagenesMascota({
      mascotaIdPg: mascotaId,
      usuarioIdPg: req.auth.userId,
      files,
      fotoPrincipalIndex: null,
    });
    for (const imagen of nuevasImagenes) {
      await client.query(
        `INSERT INTO foto_mascota (fk_mascota, storage_ref, url_preview, es_principal)
         VALUES ($1, $2, $3, FALSE)`,
        [mascotaId, imagen.storageRef, imagen.urlPreview]
    );
    }

    if (marcarComoPrincipal) {
      const nuevaPrincipal = nuevasImagenes[principalIndex];
      await client.query(
        'UPDATE foto_mascota SET es_principal = FALSE WHERE fk_mascota = $1 AND es_principal = TRUE',
        [mascotaId]
      );
      await client.query(
        'UPDATE foto_mascota SET es_principal = TRUE WHERE fk_mascota = $1 AND storage_ref = $2',
        [mascotaId, nuevaPrincipal.storageRef]
      );
      principalesMongoAnteriores = await establecerPrincipalMongo({
        mascotaId,
        usuarioId: req.auth.userId,
        imageId: nuevaPrincipal.id,
    });
    }

    await client.query('COMMIT');
    return res.status(201).json({
      ok: true,
      message: 'Fotos agregadas correctamente',
      total: nuevasImagenes.length,
    });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    await eliminarImagenesMascotaMongoPorIds(
      nuevasImagenes.map((imagen) => imagen.id)
    ).catch(() => undefined);
    if (principalesMongoAnteriores) {
      await restaurarPrincipalesMongo({
        mascotaId,
        usuarioId: req.auth.userId,
        principalIds: principalesMongoAnteriores,
      }).catch(() => undefined);
    }
    console.error('Error agregando fotos:', error);
    return res.status(500).json({ ok: false, message: 'Error agregando las fotos' });
  } finally {
    client.release();
  }
});

// =====================================================
// PUT /api/pets/:id/images/:imageId/principal
// Cambia la foto principal de una mascota.
// =====================================================
router.put('/:id/images/:imageId/principal', async (req, res) => {
    const mascotaId = Number(req.params.id);
  const imageId = req.params.imageId;
  if (!validPositiveInteger(mascotaId) || !ObjectId.isValid(imageId)) {
    return res.status(400).json({ ok: false, message: 'Identificador inválido' });
    }
  const client = await postgres.pool.connect();
  let principalesMongoAnteriores = null;
  try {
    await client.query('BEGIN');
    const mascota = await petBelongsToUser(client, mascotaId, req.auth.userId, true);
    if (!mascota || mascota.estado === 'INACTIVA') {
      await client.query('ROLLBACK');
      return res.status(404).json({ ok: false, message: 'Mascota no encontrada' });
    }
    const foto = await client.query(
      'SELECT id FROM foto_mascota WHERE fk_mascota = $1 AND storage_ref = $2',
      [mascotaId, imageId]
    );
    if (foto.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ ok: false, message: 'Foto no encontrada' });
    }
    await client.query(
      'UPDATE foto_mascota SET es_principal = FALSE WHERE fk_mascota = $1 AND es_principal = TRUE',
      [mascotaId]
    );
    await client.query(
      'UPDATE foto_mascota SET es_principal = TRUE WHERE fk_mascota = $1 AND storage_ref = $2',
      [mascotaId, imageId]
    );
    principalesMongoAnteriores = await establecerPrincipalMongo({
      mascotaId,
      usuarioId: req.auth.userId,
      imageId,
    });
    await client.query('COMMIT');
    return res.status(200).json({ ok: true, message: 'Foto principal actualizada' });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    if (principalesMongoAnteriores) {
      await restaurarPrincipalesMongo({
        mascotaId,
        usuarioId: req.auth.userId,
        principalIds: principalesMongoAnteriores,
      }).catch(() => undefined);
    }
    console.error('Error actualizando foto principal:', error);
    return res.status(500).json({ ok: false, message: 'Error actualizando la foto principal' });
  } finally {
    client.release();
  }
});

// =====================================================
// DELETE /api/pets/:id/images/:imageId
// Elimina una foto sin permitir que la mascota quede con menos de 15.
// =====================================================
router.delete('/:id/images/:imageId', async (req, res) => {
  const mascotaId = Number(req.params.id);
  const imageId = req.params.imageId;
  if (!validPositiveInteger(mascotaId) || !ObjectId.isValid(imageId)) {
    return res.status(400).json({ ok: false, message: 'Identificador inválido' });
    }
  const client = await postgres.pool.connect();
  let documentoEliminado = null;
  let principalesMongoAnteriores = null;
  try {
    await client.query('BEGIN');
    const mascota = await petBelongsToUser(client, mascotaId, req.auth.userId, true);
    if (!mascota || mascota.estado === 'INACTIVA') {
      await client.query('ROLLBACK');
      return res.status(404).json({ ok: false, message: 'Mascota no encontrada' });
    }
    const fotos = await client.query(
      `SELECT storage_ref, es_principal FROM foto_mascota
       WHERE fk_mascota = $1 ORDER BY es_principal DESC, fecha ASC FOR UPDATE`,
      [mascotaId]
    );
    const foto = fotos.rows.find((item) => item.storage_ref === imageId);
    if (!foto) {
      await client.query('ROLLBACK');
      return res.status(404).json({ ok: false, message: 'Foto no encontrada' });
    }
    if (fotos.rowCount <= MIN_IMAGES) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        ok: false,
        message: `La mascota debe conservar mínimo ${MIN_IMAGES} fotos`,
      });
    }

    const totalPrincipales = fotos.rows.filter((item) => item.es_principal).length;
    if (!foto.es_principal && totalPrincipales !== 1) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        ok: false,
        message: 'Debes establecer una única foto principal antes de eliminar otra foto',
      });
    }

    if (foto.es_principal) {
      const reemplazo = fotos.rows.find((item) => item.storage_ref !== imageId);
      await client.query(
        'UPDATE foto_mascota SET es_principal = FALSE WHERE fk_mascota = $1 AND storage_ref = $2',
        [mascotaId, imageId]
    );
      await client.query(
        'UPDATE foto_mascota SET es_principal = TRUE WHERE fk_mascota = $1 AND storage_ref = $2',
        [mascotaId, reemplazo.storage_ref]
      );
      principalesMongoAnteriores = await establecerPrincipalMongo({
        mascotaId,
        usuarioId: req.auth.userId,
        imageId: reemplazo.storage_ref,
      });
    }

    await client.query(
      'DELETE FROM foto_mascota WHERE fk_mascota = $1 AND storage_ref = $2',
      [mascotaId, imageId]
    );
    documentoEliminado = await eliminarImagenMascotaMongo({
      mascotaId,
      usuarioId: req.auth.userId,
      imageId,
    });
    await client.query('COMMIT');
    return res.status(200).json({ ok: true, message: 'Foto eliminada correctamente' });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    if (documentoEliminado) {
      await restaurarImagenMascotaMongo(documentoEliminado).catch(() => undefined);
    }
    if (principalesMongoAnteriores) {
      await restaurarPrincipalesMongo({
        mascotaId,
        usuarioId: req.auth.userId,
        principalIds: principalesMongoAnteriores,
      }).catch(() => undefined);
    }
    console.error('Error eliminando foto:', error);
    return res.status(500).json({ ok: false, message: 'Error eliminando la foto' });
  } finally {
    client.release();
  }
});

// =====================================================
// GET /api/pets/:id
// Consulta el detalle principal de una mascota.
// PostgreSQL: trae datos de mascota, especie y raza.
// =====================================================
router.get('/:id', async (req, res) => {
  const mascotaId = Number(req.params.id);
  if (!validPositiveInteger(mascotaId)) {
    return res.status(400).json({ ok: false, message: 'ID de mascota inválido' });
    }
  try {
    const result = await postgres.query(
      `SELECT m.id, m.fk_usuario, m.fk_especie, m.fk_raza, m.nombre,
        m.color, m.edad_aprox, m.unidad_edad, m.sexo, m.estado,
        m.observaciones, m.fecha_registro, e.nombre AS especie, r.nombre AS raza
       FROM mascota m
       INNER JOIN especie e ON e.id = m.fk_especie
       LEFT JOIN raza r ON r.id = m.fk_raza
       WHERE m.id = $1 AND m.fk_usuario = $2 AND m.estado <> 'INACTIVA'`,
      [mascotaId, req.auth.userId]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ ok: false, message: 'Mascota no encontrada' });
    }
    return res.status(200).json({ ok: true, mascota: result.rows[0] });
  } catch (error) {
    console.error('Error consultando mascota:', error);
    return res.status(500).json({ ok: false, message: 'Error consultando la mascota' });
    }
});

// =====================================================
// PUT /api/pets/:id
// Edita los datos principales de una mascota.
// PostgreSQL: actualiza mascota.
// MongoDB no se toca aquí, porque este endpoint solo edita datos.
// =====================================================
router.put('/:id', async (req, res) => {
  const mascotaId = Number(req.params.id);
  const especieId = Number(req.body.fk_especie);
  const razaId = req.body.fk_raza ? Number(req.body.fk_raza) : null;
  const edadAprox = req.body.edad_aprox === null || req.body.edad_aprox === ''
    ? null
    : Number(req.body.edad_aprox);
  const nombre = req.body.nombre?.trim();
  const color = req.body.color?.trim();
  if (!validPositiveInteger(mascotaId) || !validPositiveInteger(especieId) || !nombre || !color) {
    return res.status(400).json({ ok: false, message: 'Datos de mascota inválidos' });
  }
  if (razaId !== null && !validPositiveInteger(razaId)) {
    return res.status(400).json({ ok: false, message: 'La raza no es válida' });
  }
  if (edadAprox !== null && (!Number.isInteger(edadAprox) || edadAprox < 0)) {
    return res.status(400).json({ ok: false, message: 'La edad no es válida' });
  }
  const client = await postgres.pool.connect();
  try {
    await client.query('BEGIN');
    if (razaId !== null) {
      const raza = await client.query(
        'SELECT id FROM raza WHERE id = $1 AND fk_especie = $2',
        [razaId, especieId]
      );
      if (raza.rowCount === 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ ok: false, message: 'La raza no corresponde a la especie' });
      }
    }
    const result = await client.query(
      `UPDATE mascota SET
        fk_especie=$1, fk_raza=$2, nombre=$3, color=$4, edad_aprox=$5,
        unidad_edad=$6, sexo=$7, observaciones=$8, actualizado_en=NOW()
       WHERE id=$9 AND fk_usuario=$10 AND estado <> 'INACTIVA'
       RETURNING *`,
      [
      especieId,
      razaId,
        nombre,
        color,
      edadAprox,
        ['MESES', 'ANIOS'].includes(req.body.unidad_edad) ? req.body.unidad_edad : null,
        ['MACHO', 'HEMBRA', 'NO_DEFINIDO'].includes(req.body.sexo)
          ? req.body.sexo
          : 'NO_DEFINIDO',
        req.body.observaciones?.trim() || null,
      mascotaId,
        req.auth.userId,
      ]
    );
    if (result.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ ok: false, message: 'Mascota no encontrada' });
    }
    await client.query('COMMIT');
    return res.status(200).json({ ok: true, message: 'Mascota actualizada correctamente', mascota: result.rows[0] });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    console.error('Error actualizando mascota:', error);
    return res.status(500).json({ ok: false, message: 'Error actualizando la mascota' });
  } finally {
    client.release();
  }
});

// =====================================================
// DELETE /api/pets/:id
// Elimina lógicamente una mascota.
// PostgreSQL y MongoDB cambian su estado a INACTIVA.
// =====================================================
router.delete('/:id', async (req, res) => {
  const mascotaId = Number(req.params.id);
  if (!validPositiveInteger(mascotaId)) {
    return res.status(400).json({ ok: false, message: 'ID de mascota inválido' });
  }
  const client = await postgres.pool.connect();
  let imagenesInactivadas = [];
  try {
    await client.query('BEGIN');
    const mascota = await petBelongsToUser(client, mascotaId, req.auth.userId, true);
    if (!mascota) {
      await client.query('ROLLBACK');
      return res.status(404).json({ ok: false, message: 'Mascota no encontrada' });
    }
    if (mascota.estado === 'INACTIVA') {
      await client.query('ROLLBACK');
      return res.status(200).json({ ok: true, message: 'La mascota ya está inactiva' });
    }
    await client.query(
      `UPDATE mascota SET estado='INACTIVA', actualizado_en=NOW()
       WHERE id=$1 AND fk_usuario=$2`,
      [mascotaId, req.auth.userId]
    );
    const mongoResult = await inactivarImagenesMascotaMongo({
      mascotaId,
      usuarioId: req.auth.userId,
    });
    imagenesInactivadas = mongoResult.ids;
    await client.query('COMMIT');
    return res.status(200).json({ ok: true, message: 'Mascota eliminada correctamente' });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    await reactivarImagenesMascotaMongo(imagenesInactivadas).catch(() => undefined);
    console.error('Error eliminando mascota:', error);
    return res.status(500).json({ ok: false, message: 'Error eliminando la mascota' });
  } finally {
    client.release();
  }
});

module.exports = router;
