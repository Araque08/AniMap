const express = require('express');
const authRoutes = require('../modules/auth/auth.routes');

const router = express.Router();

router.get('/health', (req, res) => {
  res.status(200).json({
    ok: true,
    message: 'API funcionando',
  });
});

router.use('/auth', authRoutes);

module.exports = router;