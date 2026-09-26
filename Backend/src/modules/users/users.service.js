const db = require('../../config/postgres_db');
const { hashText } = require('../../utils/hash');

/*
  ============================================================
  ERRORES HTTP
  ============================================================
*/

function httpError(message, statusCode, code) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.code = code;
  return error;
}

/*
  ============================================================
  VALIDACIONES
  ============================================================
*/

function positiveId(value) {
  const id = Number(value);

  if (!Number.isInteger(id) || id <= 0) {
    throw httpError(
      'ID de usuario inválido',
      400,
      'INVALID_USER_ID'
    );
  }

  return id;
}

function requiredText(value, label, maxLength) {
  const text =
    typeof value === 'string'
      ? value.trim()
      : '';

  if (!text) {
    throw httpError(
      `${label} es obligatorio`,
      400,
      'INVALID_USER_INPUT'
    );
  }

  if (
    maxLength &&
    text.length > maxLength
  ) {
    throw httpError(
      `${label} supera la longitud permitida`,
      400,
      'INVALID_USER_INPUT'
    );
  }

  return text;
}

function normalizeEmail(value) {
  const email = requiredText(
    value,
    'Correo electrónico',
    150
  ).toLowerCase();

  const emailRegex =
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  if (!emailRegex.test(email)) {
    throw httpError(
      'Correo electrónico inválido',
      400,
      'INVALID_EMAIL'
    );
  }

  return email;
}

function normalizePhone(value) {
  if (
    value === undefined ||
    value === null ||
    String(value).trim() === ''
  ) {
    return null;
  }

  const phone =
    String(value).trim();

  if (phone.length > 30) {
    throw httpError(
      'Teléfono inválido',
      400,
      'INVALID_PHONE'
    );
  }

  return phone;
}

function normalizeRole(value) {
  const role =
    requiredText(
      value,
      'Rol',
      50
    ).toUpperCase();

  const allowedRoles = [
    'USUARIO',
    'ADMINISTRADOR',
  ];

  if (!allowedRoles.includes(role)) {
    throw httpError(
      'Rol inválido',
      400,
      'INVALID_ROLE'
    );
  }

  return role;
}

function normalizeStatus(value) {
  const status = requiredText(
    value,
    'Estado',
    30
  ).toUpperCase();

  const allowedStatuses = [
    'ACTIVO',
    'SUSPENDIDO',
    'ELIMINADO',
  ];

  if (!allowedStatuses.includes(status)) {
    throw httpError(
      'Estado de cuenta inválido',
      400,
      'INVALID_ACCOUNT_STATUS'
    );
  }

  return status;
}

/*
  ============================================================
  SERVICIO
  ============================================================
*/

function createUsersService(
  pool = db.pool
) {

  /*
    ==========================================================
    BITÁCORA ADMINISTRATIVA
    ==========================================================
  */

  async function writeAudit(
    client,
    adminId,
    action,
    userId
  ) {
    await client.query(
      `
        INSERT INTO bitacora_administrativa
        (
          fk_admin,
          modulo,
          accion,
          entidad_afectada,
          id_entidad_afectada
        )
        VALUES
        (
          $1,
          'USUARIOS',
          $2,
          'usuario',
          $3
        )
      `,
      [
        positiveId(adminId),
        action,
        positiveId(userId),
      ]
    );
  }

  /*
    ==========================================================
    VERIFICAR USUARIO
    ==========================================================
  */

  async function ensureUserExists(
    client,
    id,
    lock = false
  ) {
    const userId = positiveId(id);

    const result =
      await client.query(
        `
          SELECT
            id,
            nombre,
            email,
            telefono,
            is_verified,
            estado_cuenta,
            fecha_registro,
            last_login_at
          FROM usuario
          WHERE id = $1
          ${lock ? 'FOR UPDATE' : ''}
        `,
        [userId]
      );

    if (result.rowCount !== 1) {
      throw httpError(
        'Usuario no encontrado',
        404,
        'USER_NOT_FOUND'
      );
    }

    return result.rows[0];
  }

  /*
    ==========================================================
    BUSCAR ROL
    ==========================================================
  */

  async function getRoleId(
    client,
    roleName
  ) {
    const role =
      normalizeRole(roleName);

    const result =
      await client.query(
        `
          SELECT id
          FROM rol
          WHERE UPPER(nombre) = $1
          LIMIT 1
        `,
        [role]
      );

    if (result.rowCount !== 1) {
      throw httpError(
        `No existe el rol ${role}`,
        500,
        'ROLE_NOT_FOUND'
      );
    }

    return result.rows[0].id;
  }

  /*
    ==========================================================
    VALIDAR CORREO ÚNICO
    ==========================================================
  */

  async function ensureUniqueEmail(
    client,
    email,
    excludeUserId = null
  ) {
    const values = [email];

    let extraCondition = '';

    if (excludeUserId !== null) {
      values.push(
        positiveId(excludeUserId)
      );

      extraCondition =
        'AND id <> $2';
    }

    const result =
      await client.query(
        `
          SELECT id
          FROM usuario
          WHERE LOWER(email) =
                LOWER($1)
          ${extraCondition}
          LIMIT 1
        `,
        values
      );

    if (result.rowCount > 0) {
      throw httpError(
        'El correo ya está registrado',
        409,
        'EMAIL_ALREADY_EXISTS'
      );
    }
  }

  /*
    ==========================================================
    LISTAR USUARIOS
    ==========================================================
  */

  async function listUsers({
    search,
    estado,
    rol,
  } = {}) {
    const values = [];
    const conditions = [];

    if (
      search &&
      String(search).trim()
    ) {
      values.push(
        `%${String(search).trim()}%`
      );

      conditions.push(
        `
          (
            u.nombre ILIKE $${values.length}
            OR
            u.email ILIKE $${values.length}
            OR
            COALESCE(u.telefono, '')
              ILIKE $${values.length}
          )
        `
      );
    }

    if (
      estado &&
      String(estado).trim()
    ) {
      values.push(
        normalizeStatus(estado)
      );

      conditions.push(
        `u.estado_cuenta = $${values.length}`
      );
    }

    if (
      rol &&
      String(rol).trim()
    ) {
      values.push(
        normalizeRole(rol)
      );

      conditions.push(
        `UPPER(r.nombre) = $${values.length}`
      );
    }

    const where =
      conditions.length > 0
        ? `WHERE ${conditions.join(
            ' AND '
          )}`
        : '';

    const result =
      await pool.query(
        `
          SELECT
            u.id,
            u.nombre,
            u.email,
            u.telefono,
            u.is_verified,
            u.estado_cuenta,
            u.fecha_registro,
            u.last_login_at,
            COALESCE(
              r.nombre,
              'SIN ROL'
            ) AS rol

          FROM usuario u

          LEFT JOIN usuario_rol ur
            ON ur.fk_usuario = u.id

          LEFT JOIN rol r
            ON r.id = ur.fk_rol

          ${where}

          ORDER BY
            u.fecha_registro DESC,
            u.id DESC
        `,
        values
      );

    return result.rows;
  }

  /*
    ==========================================================
    OBTENER USUARIO
    ==========================================================
  */

  async function getUserById(id) {
    const userId =
      positiveId(id);

    const result =
      await pool.query(
        `
          SELECT
            u.id,
            u.nombre,
            u.email,
            u.telefono,
            u.is_verified,
            u.estado_cuenta,
            u.fecha_registro,
            u.last_login_at,
            COALESCE(
              r.nombre,
              'SIN ROL'
            ) AS rol

          FROM usuario u

          LEFT JOIN usuario_rol ur
            ON ur.fk_usuario = u.id

          LEFT JOIN rol r
            ON r.id = ur.fk_rol

          WHERE u.id = $1

          LIMIT 1
        `,
        [userId]
      );

    if (result.rowCount !== 1) {
      throw httpError(
        'Usuario no encontrado',
        404,
        'USER_NOT_FOUND'
      );
    }

    return result.rows[0];
  }

  /*
    ==========================================================
    CREAR USUARIO
    ==========================================================
  */

  async function createUser(
    data,
    adminId
  ) {
    const nombre =
      requiredText(
        data.nombre,
        'Nombre',
        150
      );

    const email =
      normalizeEmail(
        data.email
      );

    const telefono =
      normalizePhone(
        data.telefono
      );

    const role =
      normalizeRole(
        data.rol || 'USUARIO'
      );

    const password =
      requiredText(
        data.password,
        'Contraseña',
        200
      );

    if (password.length < 8) {
      throw httpError(
        'La contraseña debe tener mínimo 8 caracteres',
        400,
        'INVALID_PASSWORD'
      );
    }

    const client =
      await pool.connect();

    try {
      await client.query(
        'BEGIN'
      );

      await ensureUniqueEmail(
        client,
        email
      );

      const passwordHash =
        await hashText(password);

      const roleId =
        await getRoleId(
          client,
          role
        );

      /*
        Los usuarios creados por el administrador
        quedan verificados automáticamente.
      */

      const userResult =
        await client.query(
          `
            INSERT INTO usuario
            (
              nombre,
              email,
              telefono,
              password_hash,
              acepta_tyc,
              is_verified,
              estado_cuenta
            )
            VALUES
            (
              $1,
              $2,
              $3,
              $4,
              TRUE,
              TRUE,
              'ACTIVO'
            )
            RETURNING
              id,
              nombre,
              email,
              telefono,
              is_verified,
              estado_cuenta,
              fecha_registro,
              last_login_at
          `,
          [
            nombre,
            email,
            telefono,
            passwordHash,
          ]
        );

      const user =
        userResult.rows[0];

      /*
        Creamos perfil del usuario.
      */

      await client.query(
        `
          INSERT INTO perfil
          (
            fk_usuario,
            foto_url,
            notificaciones_activas
          )
          VALUES
          (
            $1,
            NULL,
            TRUE
          )
        `,
        [user.id]
      );

      /*
        Asociamos rol.
      */

      await client.query(
        `
          INSERT INTO usuario_rol
          (
            fk_usuario,
            fk_rol
          )
          VALUES
          (
            $1,
            $2
          )
        `,
        [
          user.id,
          roleId,
        ]
      );

      await writeAudit(
        client,
        adminId,
        'CREAR',
        user.id
      );

      await client.query(
        'COMMIT'
      );

      return {
        ...user,
        rol: role,
      };
    } catch (error) {
      await client
        .query('ROLLBACK')
        .catch(() => undefined);

      if (
        error.code === '23505'
      ) {
        throw httpError(
          'El correo ya está registrado',
          409,
          'EMAIL_ALREADY_EXISTS'
        );
      }

      throw error;
    } finally {
      client.release();
    }
  }

  /*
    ==========================================================
    ACTUALIZAR USUARIO
    ==========================================================
  */

  async function updateUser(
    id,
    data,
    adminId
  ) {
    const userId =
      positiveId(id);

    const nombre =
      requiredText(
        data.nombre,
        'Nombre',
        150
      );

    const email =
      normalizeEmail(
        data.email
      );

    const telefono =
      normalizePhone(
        data.telefono
      );

    const role =
      normalizeRole(
        data.rol
      );

    const client =
      await pool.connect();

    try {
      await client.query(
        'BEGIN'
      );

      await ensureUserExists(
        client,
        userId,
        true
      );

      await ensureUniqueEmail(
        client,
        email,
        userId
      );

      const roleId =
        await getRoleId(
          client,
          role
        );

      const result =
        await client.query(
          `
            UPDATE usuario
            SET
              nombre = $1,
              email = $2,
              telefono = $3
            WHERE id = $4
            RETURNING
              id,
              nombre,
              email,
              telefono,
              is_verified,
              estado_cuenta,
              fecha_registro,
              last_login_at
          `,
          [
            nombre,
            email,
            telefono,
            userId,
          ]
        );

      /*
        Actualizamos rol.

        Eliminamos la asociación anterior
        y creamos la nueva.
      */

      await client.query(
        `
          DELETE FROM usuario_rol
          WHERE fk_usuario = $1
        `,
        [userId]
      );

      await client.query(
        `
          INSERT INTO usuario_rol
          (
            fk_usuario,
            fk_rol
          )
          VALUES
          (
            $1,
            $2
          )
        `,
        [
          userId,
          roleId,
        ]
      );

      await writeAudit(
        client,
        adminId,
        'EDITAR',
        userId
      );

      await client.query(
        'COMMIT'
      );

      return {
        ...result.rows[0],
        rol: role,
      };
    } catch (error) {
      await client
        .query('ROLLBACK')
        .catch(() => undefined);

      if (
        error.code === '23505'
      ) {
        throw httpError(
          'El correo ya está registrado',
          409,
          'EMAIL_ALREADY_EXISTS'
        );
      }

      throw error;
    } finally {
      client.release();
    }
  }

  /*
    ==========================================================
    CAMBIAR ESTADO
    ==========================================================
  */

  async function setUserStatus(
    id,
    status,
    adminId
  ) {
    const userId =
      positiveId(id);

    const currentAdminId =
      positiveId(adminId);

    const newStatus =
      normalizeStatus(status);

    /*
      El administrador no puede
      desactivar su propia cuenta.
    */

    if (
      userId === currentAdminId &&
      newStatus !== 'ACTIVO'
    ) {
      throw httpError(
        'No puedes desactivar tu propia cuenta',
        409,
        'CANNOT_DISABLE_SELF'
      );
    }

    const client =
      await pool.connect();

    try {
      await client.query(
        'BEGIN'
      );

      await ensureUserExists(
        client,
        userId,
        true
      );

      const result =
        await client.query(
          `
            UPDATE usuario
            SET estado_cuenta = $1
            WHERE id = $2
            RETURNING
              id,
              nombre,
              email,
              telefono,
              is_verified,
              estado_cuenta,
              fecha_registro,
              last_login_at
          `,
          [
            newStatus,
            userId,
          ]
        );

      /*
        Si el usuario fue desactivado,
        invalidamos sus sesiones.
      */

      if (
    newStatus === 'SUSPENDIDO' ||
    newStatus === 'ELIMINADO'
    ) {
        await client.query(
          `
            UPDATE device_session
            SET vigente = FALSE
            WHERE
              fk_usuario = $1
              AND vigente = TRUE
          `,
          [userId]
        );
      }

      let auditAction;

    if (newStatus === 'ACTIVO') {
    auditAction = 'ACTIVAR';
    } else if (newStatus === 'SUSPENDIDO') {
    auditAction = 'SUSPENDER';
    } else {
    auditAction = 'ELIMINAR';
    }

    await writeAudit(
    client,
    adminId,
    auditAction,
    userId
    );

      await client.query(
        'COMMIT'
      );

      return result.rows[0];
    } catch (error) {
      await client
        .query('ROLLBACK')
        .catch(() => undefined);

      throw error;
    } finally {
      client.release();
    }
  }

  /*
    ==========================================================
    ELIMINACIÓN LÓGICA
    ==========================================================

    No borramos físicamente el usuario porque puede tener
    mascotas, perfiles, sesiones, reportes y otros registros
    asociados.

    DELETE simplemente deja la cuenta INACTIVA.
  */

  async function deleteUser(
    id,
    adminId
  ) {
    const userId =
      positiveId(id);

    const currentAdminId =
      positiveId(adminId);

    if (
      userId === currentAdminId
    ) {
      throw httpError(
        'No puedes eliminar tu propia cuenta',
        409,
        'CANNOT_DELETE_SELF'
      );
    }

    const client =
      await pool.connect();

    try {
      await client.query(
        'BEGIN'
      );

      await ensureUserExists(
        client,
        userId,
        true
      );

      await client.query(
        `
          UPDATE usuario
          SET estado_cuenta = 'ELIMINADO'
          WHERE id = $1
        `,
        [userId]
      );

      await client.query(
        `
          UPDATE device_session
          SET vigente = FALSE
          WHERE
            fk_usuario = $1
            AND vigente = TRUE
        `,
        [userId]
      );

      await writeAudit(
        client,
        adminId,
        'ELIMINAR',
        userId
      );

      await client.query(
        'COMMIT'
      );

      return {
        deleted: true,
        logicalDelete: true,
        id: userId,
      };
    } catch (error) {
      await client
        .query('ROLLBACK')
        .catch(() => undefined);

      throw error;
    } finally {
      client.release();
    }
  }

  return {
    listUsers,
    getUserById,
    createUser,
    updateUser,
    setUserStatus,
    deleteUser,
  };
}

module.exports = {
  createUsersService,
  usersService:
    createUsersService(),
  httpError,
};