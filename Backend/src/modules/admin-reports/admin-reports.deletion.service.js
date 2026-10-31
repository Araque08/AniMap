
const db = require('../../config/postgres_db');

const {
  duplicateReportsService,
} = require('./admin-reports.duplicates.service');

// ==========================================================
// ERRORES
// ==========================================================

function httpError(message, statusCode = 400) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function positiveId(value) {
  const id = Number(value);

  if (!Number.isSafeInteger(id) || id <= 0) {
    throw httpError('Identificador inválido');
  }

  return id;
}

// ==========================================================
// ELIMINAR UN AVISTAMIENTO DUPLICADO
// ==========================================================

async function confirmSightingDuplicate({
  registro1Id,
  registro2Id,
  conservarId,
  adminId,
  motivo,
}) {
  const firstId = positiveId(registro1Id);
  const secondId = positiveId(registro2Id);
  const keepId = positiveId(conservarId);
  const administratorId = positiveId(adminId);

  const reason = String(motivo || '').trim();

  if (firstId === secondId) {
    throw httpError('Debes seleccionar dos registros diferentes');
  }

  if (![firstId, secondId].includes(keepId)) {
    throw httpError(
      'Debes conservar uno de los dos avistamientos'
    );
  }

  if (reason.length < 10 || reason.length > 500) {
    throw httpError(
      'El motivo debe tener entre 10 y 500 caracteres'
    );
  }

  const deleteId = keepId === firstId ? secondId : firstId;

  const orderedIds = [firstId, secondId].sort((a, b) => a - b);

  const client = await db.pool.connect();

  try {
    await client.query('BEGIN');

    // Bloquear ambos registros para evitar cambios simultáneos.
    
const result = await client.query(
  `
    SELECT id, fk_usuario, estado
    FROM avistamiento
    WHERE id IN ($1, $2)
    ORDER BY id
    FOR UPDATE
  `,
  orderedIds
);

if (result.rowCount !== 2) {
  throw httpError(
    'Uno de los avistamientos no existe',
    404
  );
}

// Verificar que la pareja continúa siendo candidata.
const {
  duplicateReportsService,
} = require('./admin-reports.duplicates.service');


    // ======================================================
    // VALIDAR LA PAREJA DENTRO DE LA MISMA TRANSACCIÓN
    // ======================================================

    const matchingPair =
      await duplicateReportsService.validateSightingPair(
        client,
        orderedIds[0],
        orderedIds[1]
      );

    if (!matchingPair) {
      throw httpError(
        'Los avistamientos no cumplen los criterios de duplicación',
        409
      );
    }



    if (result.rowCount !== 2) {
      throw httpError(
        'Uno de los avistamientos no existe',
        404
      );
    }

    const deleted = result.rows.find(
      (item) => Number(item.id) === deleteId
    );

    if (
      result.rows.some(
        (item) => item.estado === 'ELIMINADO'
      )
    ) {
      throw httpError(
        'Uno de los avistamientos ya está eliminado',
        409
      );
    }

    // Registrar la decisión administrativa.
    const review = await client.query(
      `
        INSERT INTO revision_duplicados (
          tipo,
          registro_1_id,
          registro_2_id,
          registro_conservado_id,
          registro_eliminado_id,
          estado,
          motivo,
          fk_admin,
          fecha_revision
        )
        VALUES (
          'AVISTAMIENTO',
          $1, $2, $3, $4,
          'CONFIRMADO', $5, $6,
          CURRENT_TIMESTAMP
        )
        ON CONFLICT (
          tipo,
          registro_1_id,
          registro_2_id
        )
        DO NOTHING
        RETURNING id
      `,
      [
        orderedIds[0],
        orderedIds[1],
        keepId,
        deleteId,
        reason,
        administratorId,
      ]
    );

    if (review.rowCount !== 1) {
      throw httpError(
        'Esta pareja de avistamientos ya fue revisada',
        409
      );
    }

    // Eliminación lógica del registro duplicado.
    await client.query(
      `
        UPDATE avistamiento
        SET estado = 'ELIMINADO'
        WHERE id = $1
      `,
      [deleteId]
    );

    // Registrar la operación en la bitácora.
    await client.query(
      `
        INSERT INTO bitacora_administrativa (
          fk_admin,
          modulo,
          accion,
          entidad_afectada,
          id_entidad_afectada
        )
        VALUES (
          $1,
          'REPORTES',
          'ELIMINAR_DUPLICADO',
          'avistamiento',
          $2
        )
      `,
      [administratorId, deleteId]
    );

    // Crear la notificación para el usuario afectado.
    await client.query(
      `
        INSERT INTO notificacion (
          fk_usuario,
          fk_reporte,
          titulo,
          mensaje,
          leida,
          fecha,
          tipo
        )
        VALUES (
          $1,
          NULL,
          'Avistamiento duplicado eliminado',
          $2,
          FALSE,
          CURRENT_TIMESTAMP,
          'ADMINISTRATIVA'
        )
      `,
      [
        deleted.fk_usuario,
        `Tu avistamiento #${deleteId} fue retirado de AniMap ` +
        `porque un administrador confirmó que estaba duplicado. ` +
        `Se conservó el avistamiento #${keepId}. ` +
        `Motivo: ${reason}`,
      ]
    );

    // Registrar que la notificación fue creada.
    await client.query(
      `
        UPDATE revision_duplicados
        SET notificacion_enviada = TRUE
        WHERE id = $1
      `,
      [review.rows[0].id]
    );

    await client.query('COMMIT');

    return {
      ok: true,
      tipo: 'AVISTAMIENTO',
      registroConservado: keepId,
      registroEliminado: deleteId,
      mensaje: 'Duplicado eliminado correctamente',
    };

  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;

  } finally {
    client.release();
  }
}

module.exports = {
  confirmSightingDuplicate,
};
