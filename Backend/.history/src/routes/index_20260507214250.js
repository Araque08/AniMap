const express = require('express');
const authRoutes = require('../modules/auth/auth.routes');
const catalogosRoutes = require('../modules/catalogos/catalogos.routes');
const mascotasRoutes = require('../modules/pets/mascotas.routes');
const petsRoutes = require('../modules/pets/pets.routes');
const mapRoutes = require('../modules/map/map.routes');

const router = express.Router();

router.get('/health', (req, res) => {
  res.status(200).json({
    ok: true,
    message: 'API funcionando',
  });
});

router.use('/auth', authRoutes);
router.use('/catalogos', catalogosRoutes);
router.use('/pets', mascotasRoutes);
router.use('/pets', petsRoutes);
router.use('/map', mapRoutes);

module.exports = router;
