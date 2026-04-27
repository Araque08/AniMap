const express = require('express');
const router = express.Router();
const pool = require('../../config/postgres_db');

router.get('/especies', async (req, res) => {
  try {
    const result = await pool.query(`
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

router.get('/razas/:especieId', async (req, res) => {
  try {
    const { especieId } = req.params;

    const result = await pool.query(
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

module.exports = router;