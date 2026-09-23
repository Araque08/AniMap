const express = require('express');
const authMiddleware = require('../../middleware/auth.middleware');
const requireRole = require('../../middleware/role.middleware');
const controller = require('./faq.controller');

const router = express.Router();
const admin = [authMiddleware, requireRole('ADMINISTRADOR')];

router.get('/', controller.listPublic);
router.get('/categories', controller.listCategories);
router.get('/admin', admin, controller.listAdmin);
router.post('/categories', admin, controller.createCategory);
router.put('/categories/:id', admin, controller.updateCategory);
router.delete('/categories/:id', admin, controller.deleteCategory);
router.post('/', admin, controller.createFaq);
router.put('/:id', admin, controller.updateFaq);
router.patch('/:id/status', admin, controller.setFaqStatus);
router.delete('/:id', admin, controller.deleteFaq);
router.get('/:id', controller.getPublic);

module.exports = router;
