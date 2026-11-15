
const { pool } = require('../../config/postgres_db');

// =====================================================
// HU-064: REPOSITORIO DE ALERTAS COMUNITARIAS
// =====================================================

function createCommunityAlertsRepository(defaultQueryable = pool) {

  // Buscar usuarios que pueden recibir una alerta
  // cuando se registra una nueva mascota perdida.
  async function listEligibleRecipients(
    reportId,
    queryable = defaultQueryable
  ) {
    if (
      !Number.isSafeInteger(Number(reportId)) ||
      Number(reportId) <= 0
    ) {
      throw new Error('ID de reporte inválido');
    }

    const result = await queryable.query(
      `
      WITH reporte_activo AS (
        SELECT
          r.fk_usuario AS propietario_id,
          e.nombre AS especie,
          ub.lat::double precision AS lat_reporte,
          ub.lng::double precision AS lng_reporte

        FROM reporte r

        INNER JOIN mascota m
          ON m.id = r.fk_mascota

        INNER JOIN especie e
          ON e.id = m.fk_especie

        INNER JOIN ubicacion ub
          ON ub.fk_reporte = r.id

        WHERE r.id = $1
          AND r.estado = 'ACTIVO'
          AND m.estado = 'PERDIDA'
          AND ub.lat IS NOT NULL
          AND ub.lng IS NOT NULL
      ),

      candidatos AS (
        SELECT
          u.id AS usuario_id,
          ra.lat_reporte,
          ra.lng_reporte,
          pn.lat_referencia::double precision AS lat_usuario,
          pn.lng_referencia::double precision AS lng_usuario,
          pn.radio_km::double precision AS radio_km

        FROM reporte_activo ra

        INNER JOIN preferencia_notificacion pn
          ON pn.lat_referencia IS NOT NULL
          AND pn.lng_referencia IS NOT NULL

        INNER JOIN usuario u
          ON u.id = pn.fk_usuario

        INNER JOIN perfil p
          ON p.fk_usuario = u.id

        WHERE u.id <> ra.propietario_id
          AND u.estado_cuenta = 'ACTIVO'
          AND u.is_verified = TRUE
          AND p.notificaciones_activas = TRUE

          -- HU-056: Respetar filtro por especie.
          AND (
            pn.especie_filtro IS NULL
            OR LOWER(TRIM(pn.especie_filtro)) =
               LOWER(TRIM(ra.especie))
          )

          -- HU-056: Respetar eventos permitidos.
          AND (
            pn.tipo_evento IS NULL
            OR pn.tipo_evento = 'PERDIDA'
          )

          AND pn.radio_km > 0
      )

      SELECT
        c.usuario_id AS "userId",
        ROUND(dist.km::numeric, 3) AS "distanceKm"

      FROM candidatos c

      CROSS JOIN LATERAL (
        SELECT
          6371.0 * 2.0 * ASIN(
            SQRT(
              LEAST(
                1.0,
                POWER(
                  SIN(
                    RADIANS(
                      c.lat_usuario - c.lat_reporte
                    ) / 2.0
                  ),
                  2
                )
                +
                COS(RADIANS(c.lat_reporte))
                *
                COS(RADIANS(c.lat_usuario))
                *
                POWER(
                  SIN(
                    RADIANS(
                      c.lng_usuario - c.lng_reporte
                    ) / 2.0
                  ),
                  2
                )
              )
            )
          ) AS km
      ) dist

      WHERE dist.km <= c.radio_km

      ORDER BY dist.km, c.usuario_id
      `,
      [Number(reportId)]
    );

    return result.rows.map((row) => ({
      userId: Number(row.userId),
      distanceKm: Number(row.distanceKm),
    }));
  }


  // =====================================================
  // HU-064: REGISTRAR ALERTAS COMUNITARIAS PENDIENTES
  // =====================================================

  async function recordPendingAlerts(
    reportId,
    queryable = defaultQueryable
  ) {
    // Identificar usuarios cercanos que cumplen los filtros.
    const recipients = await listEligibleRecipients(
      reportId,
      queryable
    );

    if (recipients.length === 0) {
      return {
        eligibleCount: 0,
        createdCount: 0,
      };
    }

    // Consultar información básica de la mascota perdida.
    const reportResult = await queryable.query(
      `
      SELECT
        m.nombre,
        e.nombre AS especie
      FROM reporte r
      INNER JOIN mascota m
        ON m.id = r.fk_mascota
      INNER JOIN especie e
        ON e.id = m.fk_especie
      WHERE r.id = $1
        AND r.estado = 'ACTIVO'
        AND m.estado = 'PERDIDA'
      `,
      [reportId]
    );

    if (reportResult.rowCount === 0) {
      return {
        eligibleCount: 0,
        createdCount: 0,
      };
    }

    const mascota = reportResult.rows[0];

    const titulo = 'Mascota perdida cerca de ti';

    const mensaje =
      `Se reportó a ${mascota.nombre} ` +
      `(${mascota.especie}) como mascota perdida ` +
      'en Ciudad Salitre Occidental. ' +
      'Consulta el reporte en AniMap.';


    // HU-064: Restringir destinatarios durante las pruebas.
    const testing =
      process.env.FCM_TEST_MODE === 'true';

    const testRecipientId = Number(
      process.env.COMMUNITY_FCM_TEST_RECIPIENT_ID
    );

    const userIds = recipients
      .filter((recipient) => {
        // Fuera del modo de prueba, mantener
        // el comportamiento normal de AniMap.
        if (!testing) return true;

        // En pruebas, permitir únicamente
        // el destinatario configurado.
        return Number.isSafeInteger(testRecipientId) &&
          testRecipientId > 0 &&
          Number(recipient.userId) === testRecipientId;
      })
      .map((recipient) => Number(recipient.userId));


    // Registrar una sola alerta por usuario y reporte.
    const insertResult = await queryable.query(
      `
      INSERT INTO notificacion (
        fk_usuario,
        fk_reporte,
        titulo,
        mensaje,
        tipo,
        estado_envio,
        audiencia,
        fecha
      )
      SELECT
        destinatario.user_id,
        $1,
        $2,
        $3,
        'PERDIDA_CERCANA',
        'PENDIENTE',
        'COMUNIDAD',
        CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
      FROM UNNEST($4::integer[])
        AS destinatario(user_id)

      ON CONFLICT (fk_reporte, fk_usuario)
        WHERE tipo = 'PERDIDA_CERCANA'
      DO NOTHING

      RETURNING id
      `,
      [
        reportId,
        titulo,
        mensaje,
        userIds,
      ]
    );

    return {
      eligibleCount: recipients.length,
      createdCount: insertResult.rowCount,
    };
  }


  return {
  listEligibleRecipients,
  recordPendingAlerts,
    };
}

module.exports = {
  createCommunityAlertsRepository,
};
