const express = require('express');
const authMiddleware = require('../../middleware/auth.middleware');
const validateBody = require('../../middleware/validate.middleware');
const controller = require('./geofence.controller');
const { checkGeofenceSchema } = require('./geofence.schemas');

const router = express.Router();

router.post('/check', authMiddleware, validateBody(checkGeofenceSchema), controller.check);

module.exports = router;
