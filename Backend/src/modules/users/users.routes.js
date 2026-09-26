const express =
  require('express');

const authMiddleware =
  require(
    '../../middleware/auth.middleware'
  );

const requireRole =
  require(
    '../../middleware/role.middleware'
  );

const controller =
  require('./users.controller');

const router =
  express.Router();

/*
  ============================================================
  TODAS LAS RUTAS DE USUARIOS SON SOLO PARA ADMINISTRADOR
  ============================================================
*/

router.use(
  authMiddleware,
  requireRole('ADMINISTRADOR')
);

/*
  ============================================================
  CRUD
  ============================================================
*/

router.get(
  '/',
  controller.listUsers
);

router.get(
  '/:id',
  controller.getUser
);

router.post(
  '/',
  controller.createUser
);

router.put(
  '/:id',
  controller.updateUser
);

router.patch(
  '/:id/status',
  controller.setUserStatus
);

router.delete(
  '/:id',
  controller.deleteUser
);

module.exports =
  router;