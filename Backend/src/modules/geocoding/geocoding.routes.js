const express = require('express');
const authMiddleware = require('../../middleware/auth.middleware');
const controller = require('./geocoding.controller');

const router = express.Router();

router.post('/address', authMiddleware, controller.geocodeAddress);

module.exports = router;
