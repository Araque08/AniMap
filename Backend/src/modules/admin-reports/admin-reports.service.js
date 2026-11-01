
const db = require('../../config/postgres_db');

// ==========================================================
// ERRORES Y VALIDACIONES
// ==========================================================

function httpError(message, statusCode, code) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.code = code;
  return error;
}

function positiveId(value) {
  const id = Number(value);

  if (!Number.isInteger(id) || id <= 0) {
    throw httpError(
      'ID de reporte inválido',
      400,
      'INVALID_REPORT_ID'
    );
  }

  return id;
}

// ==========================================================
// SERVICIO ADMINISTRATIVO DE REPORTES
// ==========================================================

function createAdminReportsService(pool = db.pool) {

  // ========================================================
  // LISTAR Y BUSCAR REPORTES
  // ========================================================

  async function listReports({ search, estado } = {}) {
    const conditions = [];
    const values = [];

    if (search && String(search).trim()) {
      const term = `%${String(search).trim()}%`;

      values.push(term);

      conditions.push(`
        (
          CAST(r.id AS TEXT) ILIKE $${values.length}
          OR m.nombre ILIKE $${values.length}
          OR u.nombre ILIKE $${values.length}
          OR u.email ILIKE $${values.length}
          OR COALESCE(r.descripcion, '') ILIKE $${values.length}
        )
      `);
    }

    if (estado && String(estado).trim()) {
      const status = String(estado).trim().toUpperCase();

      if (!['ACTIVO', 'FINALIZADO'].includes(status)) {
        throw httpError(
          'Estado de reporte inválido',
          400,
          'INVALID_REPORT_STATUS'
        );
      }

      values.push(status);
      conditions.push(`r.estado = $${values.length}`);
    }

    const where = conditions.length
      ? `WHERE ${conditions.join(' AND ')}`
      : '';

    const result = await pool.query(
      `
        SELECT
          r.id,
          r.fk_usuario AS "usuarioId",
          r.fk_mascota AS "mascotaId",
          r.descripcion,
          r.estado,
          r.creado_en AS "creadoEn",
          r.actualizado_en AS "actualizadoEn",
          r.cerrado_en AS "cerradoEn",
          u.nombre AS "usuarioNombre",
          u.email AS "usuarioEmail",
          m.nombre AS "mascotaNombre",
          m.estado AS "mascotaEstado",
          e.nombre AS "especie",
          raza.nombre AS "raza"

        FROM reporte r

        INNER JOIN usuario u
          ON u.id = r.fk_usuario

        INNER JOIN mascota m
          ON m.id = r.fk_mascota

        INNER JOIN especie e
          ON e.id = m.fk_especie

        LEFT JOIN raza
          ON raza.id = m.fk_raza

        ${where}

        ORDER BY
          r.creado_en DESC,
          r.id DESC
      `,
      values
    );

    return result.rows;
  }

  // ========================================================
  // CONSULTAR DETALLE DE UN REPORTE
  // ========================================================

  async function getReportById(id) {
    const reportId = positiveId(id);

    const result = await pool.query(
      `
        SELECT
          r.id,
          r.fk_usuario AS "usuarioId",
          r.fk_mascota AS "mascotaId",
          r.descripcion,
          r.estado,
          r.mostrar_contacto AS "mostrarContacto",
          r.creado_en AS "creadoEn",
          r.actualizado_en AS "actualizadoEn",
          r.cerrado_en AS "cerradoEn",

          u.nombre AS "usuarioNombre",
          u.email AS "usuarioEmail",
          u.telefono AS "usuarioTelefono",

          m.nombre AS "mascotaNombre",
          m.estado AS "mascotaEstado",
          m.color AS "mascotaColor",

          e.nombre AS "especie",
          raza.nombre AS "raza",

          ub.metodo AS "ubicacionMetodo",
          ub.lat AS "latitud",
          ub.lng AS "longitud",
          ub.direccion,

          (
            SELECT COUNT(*)::int
            FROM avistamiento av
            WHERE av.fk_reporte_perdida = r.id
          ) AS "totalAvistamientos"

        FROM reporte r

        INNER JOIN usuario u
          ON u.id = r.fk_usuario

        INNER JOIN mascota m
          ON m.id = r.fk_mascota

        INNER JOIN especie e
          ON e.id = m.fk_especie

        LEFT JOIN raza
          ON raza.id = m.fk_raza

        LEFT JOIN ubicacion ub
          ON ub.fk_reporte = r.id

        WHERE r.id = $1
      `,
      [reportId]
    );

    if (result.rowCount === 0) {
      throw httpError(
        'Reporte no encontrado',
        404,
        'REPORT_NOT_FOUND'
      );
    }

    return result.rows[0];
  }

  
  // ========================================================
  // HU-076: ACTUALIZAR ESTADOS DE REPORTE Y MASCOTA
  // ========================================================

  async function updateReportStatus(
    reportId,
    data,
    adminId
  ) {
    const id = positiveId(reportId);
    const administratorId = positiveId(adminId);

    const reportStatus = String(
      data?.estadoReporte ?? ''
    ).trim().toUpperCase();

    const petStatus = String(
      data?.estadoMascota ?? ''
    ).trim().toUpperCase();

    const allowedCombinations = {
      ACTIVO: ['PERDIDA'],
      FINALIZADO: ['ACTIVA', 'ENCONTRADA'],
    };

    if (
      !allowedCombinations[reportStatus] ||
      !allowedCombinations[reportStatus].includes(petStatus)
    ) {
      throw httpError(
        'Los estados del reporte y la mascota no son compatibles',
        400,
        'INVALID_STATUS_COMBINATION'
      );
    }

    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Buscar la mascota asociada al reporte.
      const reference = await client.query(
        `
          SELECT fk_mascota
          FROM reporte
          WHERE id = $1
        `,
        [id]
      );

      if (reference.rowCount !== 1) {
        throw httpError(
          'Reporte no encontrado',
          404,
          'REPORT_NOT_FOUND'
        );
      }

      const petId = reference.rows[0].fk_mascota;

      // Bloquear la mascota durante la operación.
      const petResult = await client.query(
        `
          SELECT id, estado
          FROM mascota
          WHERE id = $1
          FOR UPDATE
        `,
        [petId]
      );

      if (petResult.rowCount !== 1) {
        throw httpError(
          'Mascota no encontrada',
          404,
          'PET_NOT_FOUND'
        );
      }

      if (petResult.rows[0].estado === 'INACTIVA') {
        throw httpError(
          'No se puede modificar una mascota inactiva',
          409,
          'PET_INACTIVE'
        );
      }

      // Bloquear el reporte y consultar su estado actual.
      const currentResult = await client.query(
        `
          SELECT id, fk_mascota, estado
          FROM reporte
          WHERE id = $1
          FOR UPDATE
        `,
        [id]
      );

      if (
        currentResult.rowCount !== 1 ||
        currentResult.rows[0].fk_mascota !== petId
      ) {
        throw httpError(
          'El reporte no está disponible',
          409,
          'REPORT_CONFLICT'
        );
      }

      const previousReportStatus =
        currentResult.rows[0].estado;

      const previousPetStatus =
        petResult.rows[0].estado;

      // Si existe otro reporte activo, impedir conflictos.
      if (reportStatus === 'ACTIVO') {
        const activeResult = await client.query(
          `
            SELECT id
            FROM reporte
            WHERE fk_mascota = $1
              AND estado = 'ACTIVO'
              AND id <> $2
            LIMIT 1
          `,
          [petId, id]
        );

        if (activeResult.rowCount > 0) {
          throw httpError(
            'La mascota ya tiene otro reporte activo',
            409,
            'ACTIVE_REPORT_EXISTS'
          );
        }
      }

      // Evitar acciones innecesarias.
      if (
        previousReportStatus === reportStatus &&
        previousPetStatus === petStatus
      ) {
        throw httpError(
          'Los estados seleccionados ya están registrados',
          409,
          'NO_CHANGES'
        );
      }

      // Actualizar el estado del reporte.
      
        const updatedReport = await client.query(
        `
            UPDATE reporte
            SET
            estado = $1::estado_reporte_enum,
            cerrado_en = CASE
                WHEN $1::estado_reporte_enum = 'FINALIZADO'::estado_reporte_enum
                THEN COALESCE(
                    cerrado_en,
                    CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
                )
                ELSE NULL
            END,
            actualizado_en =
                CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
            WHERE id = $2
            RETURNING id, estado
        `,
        [reportStatus, id]
        );


      // Actualizar el estado de la mascota.
      await client.query(
        `
          UPDATE mascota
          SET
            estado = $1,
            actualizado_en =
              CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
          WHERE id = $2
        `,
        [petStatus, petId]
      );

      // Registrar la operación administrativa.
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
            'REPORTES',
            $2,
            'reporte',
            $3
          )
        `,
        [
          administratorId,
          `CAMBIO_ESTADO_${previousReportStatus}_A_${reportStatus}_MASCOTA_${previousPetStatus}_A_${petStatus}`,
          id,
        ]
      );

      await client.query('COMMIT');

      return {
        id: updatedReport.rows[0].id,
        estadoReporte: reportStatus,
        mascotaId: petId,
        estadoMascota: petStatus,
        message: 'Estados actualizados correctamente',
      };

    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);

      if (error.code === '23505') {
        throw httpError(
          'La mascota ya tiene un reporte activo',
          409,
          'ACTIVE_REPORT_EXISTS'
        );
      }

      throw error;

    } finally {
      client.release();
    }
  }


    return {
    listReports,
    getReportById,
    updateReportStatus,
  };
}

module.exports = {
  createAdminReportsService,
  adminReportsService: createAdminReportsService(),
};
