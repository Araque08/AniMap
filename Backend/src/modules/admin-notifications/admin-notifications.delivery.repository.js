
const { createHash } = require('node:crypto');

// =====================================================
// HU-049: PREPARAR ENTREGAS PUSH ADMINISTRATIVAS
// =====================================================

// Recibe el cliente PostgreSQL de la transacción
// y los IDs de las notificaciones recién creadas.
//
// NO realiza envíos a Firebase.

async function planificarEntregas(client, notificacionIds) {
  if (!Array.isArray(notificacionIds) ||
      notificacionIds.length === 0) {
    return 0;
  }

  const resultado = await client.query(
    `
    WITH dispositivos AS (
      SELECT
        n.id AS notificacion_id,
        ds.id AS sesion_id,
        ds.fcm_registration_id,

        ROW_NUMBER() OVER (
          PARTITION BY n.id, ds.fcm_registration_id
          ORDER BY ds.id DESC
        ) AS posicion

      FROM notificacion n

      INNER JOIN device_session ds
        ON ds.fk_usuario = n.fk_usuario

      WHERE n.id = ANY($1::integer[])
        AND n.tipo = 'ADMINISTRATIVA'
        AND ds.vigente = TRUE
        AND ds.expira_en >
          (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
        AND ds.fcm_registration_id IS NOT NULL
        AND BTRIM(ds.fcm_registration_id) <> ''
    )

    INSERT INTO notificacion_entrega (
      fk_notificacion,
      fk_device_session,
      registro_huella,
      estado
    )

    SELECT
      notificacion_id,
      sesion_id,

      ENCODE(
        SHA256(
          CONVERT_TO(fcm_registration_id, 'UTF8')
        ),
        'hex'
      ),

      'PENDIENTE'

    FROM dispositivos
    WHERE posicion = 1

    ON CONFLICT (
      fk_notificacion,
      registro_huella
    )
    DO NOTHING

    RETURNING id
    `,
    [notificacionIds]
  );

  return resultado.rowCount;
}

module.exports = {
  planificarEntregas
};
