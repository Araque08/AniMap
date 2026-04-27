const express = require('express');
const authRoutes = require('../modules/auth/auth.routes');
const catalogosRoutes = require('../modules/catalogos/catalogos.routes');
const mascotasRoutes = require('../modules/pets/mascotas.routes');

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

module.exports = router;


