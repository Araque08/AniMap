const express = require('express');
const { getMongoDb } = require('../../config/mongo_db');
const pool = require('../../config/postgres_db');

const router = express.Router();

// GET /api/pets/my?usuarioId=1
router.get('/my', async (req, res) => {
  try {
    const usuarioId = Number(req.query.usuarioId);

    if (!usuarioId) {
      return res.status(400).json({
        ok: false,
        message: 'Debe enviar un usuarioId válido',
      });
    }

    // 1. Buscar datos principales en PostgreSQL
    const queryMascotas = `
      SELECT
        m.id,
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

    // 2. Tomar conexión directa a la colección de MongoDB
    const imagenesMascotaCollection = db.collection('ImagenMascota');

    // 3. Por cada mascota de PostgreSQL, buscar su imagen principal en MongoDB
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

// GET /api/pets/images/:imageId
router.get('/images/:imageId', async (req, res) => {
  try {
    const { ObjectId } = require('mongodb');
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

module.exports = router;