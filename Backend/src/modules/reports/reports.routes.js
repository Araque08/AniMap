const express = require('express');
const authMiddleware = require('../../middleware/auth.middleware');
const validateBody = require('../../middleware/validate.middleware');
const controller = require('./reports.controller');
const {
  createReportSchema,
  updateReportSchema,
} = require('./reports.schemas');

const router = express.Router();

router.use(authMiddleware);
router.get('/pets', controller.listReportablePets);
router.get('/my', controller.listOwnReports);
router.get('/:id', controller.getOwnReport);
router.post('/', validateBody(createReportSchema), controller.createReport);
router.patch('/:id', validateBody(updateReportSchema), controller.updateReport);
router.post('/:id/close', controller.closeReport);

module.exports = router;
