const multer = require('multer');
const express = require('express');
const { ObjectId } = require('mongodb');
const { getMongoDb } = require('../../config/mongo_db');
const pool = require('../../config/postgres_db');
const { guardarImagenesMascota } = require('./pets.images.repository');

const router = express.Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 5 * 1024 * 1024,
  },
});

// =====================================================
// GET /api/pets/my?usuarioId=1
// Lista las mascotas del usuario.
// PostgreSQL: datos de mascota, especie y raza.
// MongoDB: imagen principal.
// =====================================================
router.get('/my', async (req, res) => {
  try {
    const usuarioId = Number(req.query.usuarioId);

    if (!usuarioId) {
      return res.status(400).json({
        ok: false,
        message: 'Debe enviar un usuarioId válido',
      });
    }

    const queryMascotas = `
      SELECT
        m.id,
        m.fk_usuario,
        m.fk_especie,
        m.fk_raza,
        m.nombre,
        m.color,
        m.edad_aprox,
        m.unidad_edad,
        m.sexo,
        m.estado,
        m.observaciones,
        m.fecha_registro,
        e.nombre AS especie,
        r.nombre AS raza
      FROM mascota m
      INNER JOIN especie e
        ON e.id = m.fk_especie
      LEFT JOIN raza r
        ON r.id = m.fk_raza
      WHERE m.fk_usuario = $1
      ORDER BY m.fecha_registro DESC;
    `;

    const result = await pool.query(queryMascotas, [usuarioId]);
    const mascotasPg = result.rows;

    const db = await getMongoDb();
    const imagenesMascotaCollection = db.collection('ImagenMascota');

    const mascotas = await Promise.all(
      mascotasPg.map(async (mascota) => {
        const imagenPrincipal = await imagenesMascotaCollection.findOne({
          mascotaIdPg: mascota.id,
          usuarioIdPg: usuarioId,
          esPrincipal: true,
          estado: 'ACTIVA',
        });

        return {
          id: mascota.id,
          fk_usuario: mascota.fk_usuario,
          fk_especie: mascota.fk_especie,
          fk_raza: mascota.fk_raza,
          nombre: mascota.nombre,
          color: mascota.color,
          edad_aprox: mascota.edad_aprox,
          unidad_edad: mascota.unidad_edad,
          sexo: mascota.sexo,
          estado: mascota.estado,
          observaciones: mascota.observaciones,
          fecha_registro: mascota.fecha_registro,
          especie: mascota.especie,
          raza: mascota.raza,
          fotoPrincipal: imagenPrincipal
            ? {
                id: imagenPrincipal._id,
                url: `/api/pets/images/${imagenPrincipal._id}`,
                nombreArchivo: imagenPrincipal.nombreArchivo || null,
                mimeType: imagenPrincipal.mimeType || 'image/jpeg',
              }
            : null,
        };
      })
    );

    return res.status(200).json({
      ok: true,
      total: mascotas.length,
      mascotas,
    });
  } catch (error) {
    console.error('Error consultando mascotas:', error);

    return res.status(500).json({
      ok: false,
      message: 'Error consultando las mascotas registradas',
    });
  }
});

// =====================================================
// GET /api/pets/images/:imageId
// Retorna una imagen guardada en MongoDB.
// =====================================================
router.get('/images/:imageId', async (req, res) => {
  try {
    const { imageId } = req.params;

    if (!ObjectId.isValid(imageId)) {
      return res.status(400).json({
        ok: false,
        message: 'ID de imagen inválido',
      });
    }

    const db = await getMongoDb();
    const imagenesMascotaCollection = db.collection('ImagenMascota');

    const imagen = await imagenesMascotaCollection.findOne({
      _id: new ObjectId(imageId),
    });

    if (!imagen || !imagen.imagen) {
      return res.status(404).json({
        ok: false,
        message: 'Imagen no encontrada',
      });
    }

    res.set('Content-Type', imagen.mimeType || 'image/jpeg');
    res.set('Cache-Control', 'public, max-age=86400');

    return res.send(imagen.imagen);
  } catch (error) {
    console.error('Error consultando imagen de mascota:', error);

    return res.status(500).json({
      ok: false,
      message: 'Error consultando la imagen de la mascota',
    });
  }
});

// =====================================================
// GET /api/pets/:id/images?usuarioId=1
// Lista todas las imágenes de una mascota desde MongoDB.
// No devuelve el Buffer completo aquí, solo las URLs para mostrarlas.
// =====================================================
router.get('/:id/images', async (req, res) => {
  try {
    const mascotaId = Number(req.params.id);
    const usuarioId = Number(req.query.usuarioId);

    if (!mascotaId) {
      return res.status(400).json({
        ok: false,
        message: 'ID de mascota inválido',
      });
    }

    if (!usuarioId) {
      return res.status(400).json({
        ok: false,
        message: 'Debe enviar un usuarioId válido',
      });
    }

    const db = await getMongoDb();
    const imagenesMascotaCollection = db.collection('ImagenMascota');

    const imagenes = await imagenesMascotaCollection
      .find({
        mascotaIdPg: mascotaId,
        usuarioIdPg: usuarioId,
        estado: 'ACTIVA',
      })
      .project({
        imagen: 0, // importante: no mandamos el Buffer pesado en el JSON
      })
      .sort({
        esPrincipal: -1,
        createdAt: 1,
        fecha: 1,
      })
      .toArray();

    const imagenesResponse = imagenes.map((img) => ({
      id: img._id,
      url: `/api/pets/images/${img._id}`,
      nombreArchivo: img.nombreArchivo || null,
      mimeType: img.mimeType || 'image/jpeg',
      esPrincipal: img.esPrincipal === true,
      estado: img.estado || 'ACTIVA',
      fecha: img.fecha || img.createdAt || null,
    }));

    return res.status(200).json({
      ok: true,
      total: imagenesResponse.length,
      imagenes: imagenesResponse,
    });
  } catch (error) {
    console.error('Error consultando imágenes de mascota:', error);

    return res.status(500).json({
      ok: false,
      message: 'Error consultando las imágenes de la mascota',
    });
  }
});

// =====================================================
// POST /api/pets/:id/images
// Agrega nuevas fotos a una mascota existente.
// =====================================================
router.post('/:id/images', upload.array('imagenes', 30), async (req, res) => {
  try {
    const mascotaId = Number(req.params.id);
    const fkUsuario = Number(req.body.fk_usuario);

    const fotoPrincipalIndex = req.body.foto_principal_index !== undefined
      ? Number(req.body.foto_principal_index)
      : 0;

    const marcarComoPrincipal =
      req.body.marcar_como_principal === true ||
      req.body.marcar_como_principal === 'true';

    console.log('Mascota ID:', mascotaId);
    console.log('Usuario ID:', fkUsuario);
    console.log('Archivos recibidos:', req.files?.length || 0);
    console.log('Foto principal index:', fotoPrincipalIndex);
    console.log('Marcar como principal:', marcarComoPrincipal);

    if (!mascotaId) {
      return res.status(400).json({
        ok: false,
        message: 'ID de mascota inválido',
      });
    }

    if (!fkUsuario) {
      return res.status(400).json({
        ok: false,
        message: 'Debe enviar el usuario propietario de la mascota',
      });
    }

    if (!req.files || req.files.length === 0) {
      return res.status(400).json({
        ok: false,
        message: 'Debe enviar al menos una imagen',
      });
    }

    const mascotaResult = await pool.query(
      `
      SELECT id, fk_usuario
      FROM mascota
      WHERE id = $1
        AND fk_usuario = $2
      `,
      [mascotaId, fkUsuario]
    );

    if (mascotaResult.rows.length === 0) {
      return res.status(404).json({
        ok: false,
        message: 'Mascota no encontrada o no pertenece al usuario indicado',
      });
    }

    const totalGuardadas = await guardarImagenesMascota({
      mascotaIdPg: mascotaId,
      usuarioIdPg: fkUsuario,
      files: req.files,
      fotoPrincipalIndex,
      marcarComoPrincipal,
    });

    return res.status(201).json({
      ok: true,
      message: 'Fotos agregadas correctamente',
      total: totalGuardadas,
    });
  } catch (error) {
    console.error('Error agregando fotos a mascota:', error);

    return res.status(500).json({
      ok: false,
      message: 'Error agregando fotos a la mascota',
      error: error.message,
      stack: error.stack,
    });
  }
});

// =====================================================
// GET /api/pets/:id
// Consulta el detalle principal de una mascota.
// PostgreSQL: trae datos de mascota, especie y raza.
// =====================================================
router.get('/:id', async (req, res) => {
  try {
    const mascotaId = Number(req.params.id);

    if (!mascotaId) {
      return res.status(400).json({
        ok: false,
        message: 'ID de mascota inválido',
      });
    }

    const query = `
      SELECT
        m.id,
        m.fk_usuario,
        m.fk_especie,
        m.fk_raza,
        m.nombre,
        m.color,
        m.edad_aprox,
        m.unidad_edad,
        m.sexo,
        m.estado,
        m.observaciones,
        m.fecha_registro,
        e.nombre AS especie,
        r.nombre AS raza
      FROM mascota m
      INNER JOIN especie e ON e.id = m.fk_especie
      LEFT JOIN raza r ON r.id = m.fk_raza
      WHERE m.id = $1
      LIMIT 1;
    `;

    const result = await pool.query(query, [mascotaId]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        ok: false,
        message: 'Mascota no encontrada',
      });
    }

    return res.status(200).json({
      ok: true,
      mascota: result.rows[0],
    });
  } catch (error) {
    console.error('Error consultando mascota:', error);

    return res.status(500).json({
      ok: false,
      message: 'Error consultando la mascota',
      error: error.message,
    });
  }
});

// =====================================================
// delete /api/pets/:id
// Elimina una mascota.
// PostgreSQL: elimina mascota.
// MongoDB elimina las imágenes asociadas a esa mascota (estado INACTIVA).
// =====================================================


router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { fk_usuario } = req.body;

    if (!fk_usuario) {
      return res.status(400).json({
        ok: false,
        message: 'El usuario es obligatorio para eliminar la mascota',
      });
    }

    const mascotaResult = await pool.query(
      `
      SELECT id, nombre, fk_usuario
      FROM mascota
      WHERE id = $1
        AND fk_usuario = $2
      `,
      [id, fk_usuario]
    );

    if (mascotaResult.rowCount === 0) {
      return res.status(404).json({
        ok: false,
        message: 'Mascota no encontrada o no pertenece al usuario',
      });
    }

    await pool.query(
      `
      DELETE FROM mascota
      WHERE id = $1
        AND fk_usuario = $2
      `,
      [id, fk_usuario]
    );

    return res.status(200).json({
      ok: true,
      message: 'Mascota eliminada correctamente',
    });
  } catch (error) {
    console.error('Error eliminando mascota:', error);

    return res.status(500).json({
      ok: false,
      message: 'Error eliminando mascota',
      error: error.message,
    });
  }
});

// =====================================================
// PUT /api/pets/:id
// Edita los datos principales de una mascota.
// PostgreSQL: actualiza mascota.
// MongoDB no se toca aquí, porque este endpoint solo edita datos.
// =====================================================
router.put('/:id', async (req, res) => {
  try {
    const mascotaId = Number(req.params.id);

    const {
      fk_usuario,
      fk_especie,
      fk_raza,
      nombre,
      color,
      edad_aprox,
      unidad_edad,
      sexo,
      observaciones,
    } = req.body;

    if (!mascotaId) {
      return res.status(400).json({
        ok: false,
        message: 'ID de mascota inválido',
      });
    }

    if (!fk_usuario) {
      return res.status(400).json({
        ok: false,
        message: 'Debe enviar el usuario propietario de la mascota',
      });
    }

    if (!fk_especie || !nombre || !color) {
      return res.status(400).json({
        ok: false,
        message: 'Especie, nombre y color son obligatorios',
      });
    }

    const especieId = Number(fk_especie);
    const razaId =
      fk_raza !== null && fk_raza !== undefined && fk_raza !== ''
        ? Number(fk_raza)
        : null;

    const edadAprox =
      edad_aprox !== null && edad_aprox !== undefined && edad_aprox !== ''
        ? Number(edad_aprox)
        : null;

    if (!especieId) {
      return res.status(400).json({
        ok: false,
        message: 'La especie enviada no es válida',
      });
    }

    if (razaId !== null && Number.isNaN(razaId)) {
      return res.status(400).json({
        ok: false,
        message: 'La raza enviada no es válida',
      });
    }

    if (edadAprox !== null && Number.isNaN(edadAprox)) {
      return res.status(400).json({
        ok: false,
        message: 'La edad aproximada no es válida',
      });
    }

    const unidadEdadFinal =
      unidad_edad === 'MESES' || unidad_edad === 'ANIOS'
        ? unidad_edad
        : null;

    const sexoFinal = ['MACHO', 'HEMBRA', 'NO_DEFINIDO'].includes(sexo)
      ? sexo
      : 'NO_DEFINIDO';

    const queryUpdate = `
      UPDATE mascota
      SET
        fk_especie = $1,
        fk_raza = $2,
        nombre = $3,
        color = $4,
        edad_aprox = $5,
        unidad_edad = $6,
        sexo = $7,
        observaciones = $8
      WHERE id = $9
        AND fk_usuario = $10
      RETURNING
        id,
        fk_usuario,
        fk_especie,
        fk_raza,
        nombre,
        color,
        edad_aprox,
        unidad_edad,
        sexo,
        estado,
        observaciones,
        fecha_registro;
    `;

    const values = [
      especieId,
      razaId,
      nombre.trim(),
      color.trim(),
      edadAprox,
      unidadEdadFinal,
      sexoFinal,
      observaciones?.trim() || null,
      mascotaId,
      Number(fk_usuario),
    ];

    const result = await pool.query(queryUpdate, values);

    if (result.rows.length === 0) {
      return res.status(404).json({
        ok: false,
        message: 'Mascota no encontrada o no pertenece al usuario indicado',
      });
    }

    return res.status(200).json({
      ok: true,
      message: 'Mascota actualizada correctamente',
      mascota: result.rows[0],
    });
  } catch (error) {
    console.error('Error actualizando mascota:', error);

    return res.status(500).json({
      ok: false,
      message: 'Error actualizando la mascota',
    });
  }
});

module.exports = router;