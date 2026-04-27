const express = require('express');
const multer = require('multer');
const pool = require('../../config/postgres_db');
const { guardarImagenesMascota } = require('./pets.images.repository');

const router = express.Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 5 * 1024 * 1024,
  },
});


router.post('/', upload.array('imagenes', 30), async (req, res) => {
  try {
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

    if (!fk_usuario || !fk_especie || !nombre || !color) {
      return res.status(400).json({
        ok: false,
        message: 'Nombre, especie, color y usuario son obligatorios',
      });
    }

    if (!req.files || req.files.length < 6) {
      return res.status(400).json({
        ok: false,
        message: 'Debes cargar mínimo 6 imágenes',
      });
    }

    const mascotaResult = await pool.query(
      `
      INSERT INTO mascota (
        fk_usuario,
        fk_especie,
        fk_raza,
        nombre,
        color,
        edad_aprox,
        unidad_edad,
        sexo,
        observaciones
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
      RETURNING id
      `,
      [
        fk_usuario,
        fk_especie,
        fk_raza || null,
        nombre,
        color,
        edad_aprox || null,
        unidad_edad || null,
        sexo || 'NO_DEFINIDO',
        observaciones || null,
      ]
    );

    const mascotaId = mascotaResult.rows[0].id;

 
    const imagenesGuardadas = await guardarImagenesMascota({
        mascotaIdPg: mascotaId,
        usuarioIdPg: fk_usuario,
        files: req.files,
    });

    return res.status(201).json({
      ok: true,
      message: 'Mascota registrada exitosamente',
      mascotaId,
      imagenesGuardadas,
    });
  } catch (error) {
    console.error('Error registrando mascota:', error);

    return res.status(500).json({
      ok: false,
      message: 'Error interno del servidor',
    });
  }
});

module.exports = router;