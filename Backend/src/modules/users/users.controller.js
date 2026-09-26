const {
  usersService,
} = require('./users.service');

/*
  ============================================================
  CONTROLADOR GENÉRICO
  ============================================================
*/

function handle(action) {
  return async (
    req,
    res,
    next
  ) => {
    try {
      const {
        status = 200,
        data,
      } = await action(req);

      return res
        .status(status)
        .json({
          ok: true,
          data,
        });
    } catch (error) {
      next(error);
    }
  };
}

/*
  ============================================================
  CONTROLADORES
  ============================================================
*/

module.exports = {

  /*
    GET /api/users
  */

  listUsers: handle(
    async (req) => ({
      data:
        await usersService.listUsers({
          search:
            req.query.search,
          estado:
            req.query.estado,
          rol:
            req.query.rol,
        }),
    })
  ),

  /*
    GET /api/users/:id
  */

  getUser: handle(
    async (req) => ({
      data:
        await usersService.getUserById(
          req.params.id
        ),
    })
  ),

  /*
    POST /api/users
  */

  createUser: handle(
    async (req) => ({
      status: 201,

      data:
        await usersService.createUser(
          req.body,
          req.auth.userId
        ),
    })
  ),

  /*
    PUT /api/users/:id
  */

  updateUser: handle(
    async (req) => ({
      data:
        await usersService.updateUser(
          req.params.id,
          req.body,
          req.auth.userId
        ),
    })
  ),

  /*
    PATCH /api/users/:id/status
  */

  setUserStatus: handle(
    async (req) => ({
      data:
        await usersService.setUserStatus(
          req.params.id,
          req.body.estado,
          req.auth.userId
        ),
    })
  ),

  /*
    DELETE /api/users/:id
  */

  deleteUser: handle(
    async (req) => ({
      data:
        await usersService.deleteUser(
          req.params.id,
          req.auth.userId
        ),
    })
  ),
};