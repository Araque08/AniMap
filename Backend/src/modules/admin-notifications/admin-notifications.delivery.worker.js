
const { createHash } = require('node:crypto');
const db = require('../../config/postgres_db');

const {
  createFirebaseSender,
  classifyFirebaseError
} = require('../notifications/firebase.sender');

// =====================================================
// HU-049: PROCESADOR DE NOTIFICACIONES ADMINISTRATIVAS
// =====================================================

// Este módulo NO se ejecuta automáticamente.
// No se conecta al servidor ni inicia temporizadores.

function idValido(valor) {
  const numero = Number(valor);

  return Number.isSafeInteger(numero) &&
    numero > 0 &&
    numero <= 2147483647;
}

function createAdminDeliveryWorker({
  pool = db.pool,
  enabled = process.env.ADMIN_FCM_ENABLED,
  qaUserId = process.env.ADMIN_FCM_QA_USER_ID,
  qaNotificationId = process.env.ADMIN_FCM_QA_NOTIFICATION_ID,
  sender = null,
  now = Date.now,
  random = Math.random
} = {}) {


  // ===================================================
  // ACTUALIZAR AUDITORÍA SEGÚN LAS ENTREGAS FIREBASE
  // ===================================================

  async function actualizarAuditoria(queryable, notificacionId) {
    const resultado = await queryable.query(
      `
      WITH auditoria AS (
        SELECT
          b.id,
          b.detalle::jsonb AS datos
        FROM bitacora_administrativa b
        WHERE b.modulo = 'NOTIFICACIONES'
          AND b.accion = 'ENVIO_ADMINISTRATIVO'
          AND COALESCE(
            b.detalle::jsonb -> 'notificacionIds',
            '[]'::jsonb
          ) @> jsonb_build_array($1::integer)
      ),

      resumen AS (
        SELECT
          a.id,

          COUNT(d.id) FILTER (
            WHERE d.estado = 'ACEPTADA_FCM'
          )::int AS aceptadas,

          COUNT(d.id) FILTER (
            WHERE d.estado = 'FALLIDA_PERMANENTE'
          )::int AS fallidas,

          COUNT(d.id) FILTER (
            WHERE d.estado = 'INDETERMINADA'
          )::int AS indeterminadas,

          COUNT(d.id) FILTER (
            WHERE d.estado = 'OMITIDA'
          )::int AS omitidas,

          COUNT(d.id) FILTER (
            WHERE d.estado IN (
              'PENDIENTE',
              'REINTENTO',
              'EN_PROCESO'
            )
          )::int AS pendientes

        FROM auditoria a

        LEFT JOIN LATERAL jsonb_array_elements_text(
          COALESCE(
            a.datos -> 'notificacionIds',
            '[]'::jsonb
          )
        ) AS x(notificacion_id) ON TRUE

        LEFT JOIN notificacion_entrega d
          ON d.fk_notificacion =
            x.notificacion_id::integer

        GROUP BY a.id
      )

      UPDATE bitacora_administrativa b

      SET detalle = (
        b.detalle::jsonb ||

        jsonb_build_object(
          'entregasPlanificadasFCM',
          COALESCE(
            (b.detalle::jsonb ->
              'entregasPlanificadasFCM')::text::integer,
            (b.detalle::jsonb ->>
              'entregasPendientesFCM')::integer,
            0
          ),

          'entregasPendientesFCM', r.pendientes,
          'entregasAceptadasFCM', r.aceptadas,
          'entregasFallidasFCM', r.fallidas,
          'entregasIndeterminadasFCM', r.indeterminadas,
          'entregasOmitidasFCM', r.omitidas,

          'pushEnviado', r.aceptadas > 0,
          'pushAceptadoPorFCM', r.aceptadas > 0,

          'estado',
            CASE
              WHEN r.pendientes > 0
                THEN 'FCM_PENDIENTE'
              WHEN r.indeterminadas > 0
                THEN 'FCM_INDETERMINADA'
              WHEN r.aceptadas > 0
                AND r.fallidas = 0
                AND r.omitidas = 0
                THEN 'ACEPTADA_FCM'
              WHEN r.aceptadas > 0
                THEN 'FCM_PARCIAL'
              WHEN r.fallidas > 0
                THEN 'FCM_FALLIDA'
              WHEN r.omitidas > 0
                THEN 'FCM_OMITIDA'
              ELSE 'REGISTRADO_EN_APP'
            END
        )
      )::text

      FROM resumen r
      WHERE b.id = r.id

      RETURNING b.id
      `,
      [notificacionId]
    );

    if (resultado.rowCount !== 1) {
      throw new Error(
        'No se pudo actualizar la auditoría Firebase'
      );
    }
  }

  // ===================================================
  // FINALIZAR ENTREGA Y ACTUALIZAR AUDITORÍA
  // ===================================================


  // ===================================================
  // HU-049: FINALIZAR ENTREGA Y AUDITORÍA ATÓMICAMENTE
  // ===================================================

  async function finalizar(entrega, resultado) {
    const client = await pool.connect();
    let transaccionAbierta = false;

    try {
      await client.query('BEGIN');
      transaccionAbierta = true;

      // Actualizar la entrega únicamente si continúa
      // reclamada con el número de intentos esperado.
      const actualizado = await client.query(
        `
        UPDATE notificacion_entrega
        SET
          estado = $3,
          ultimo_error = $4,
          proximo_intento_en = $5::timestamp,
          fcm_message_id = $6,
          aceptado_en = $7::timestamp

        WHERE id = $1
          AND intentos = $2
          AND estado = 'EN_PROCESO'

        RETURNING id, fk_notificacion
        `,
        [
          entrega.id,
          entrega.intentos,
          resultado.estado,
          resultado.error ?? null,
          resultado.proximoIntento ?? null,
          resultado.mensajeId ?? null,
          resultado.aceptadoEn ?? null
        ]
      );

      if (actualizado.rowCount !== 1) {
        throw new Error(
          'No se pudo confirmar el estado de la entrega'
        );
      }

      const notificacionId = Number(
        actualizado.rows[0].fk_notificacion
      );

      // Actualizar la auditoría dentro de la misma
      // transacción PostgreSQL.
      await actualizarAuditoria(
        client,
        notificacionId
      );

      // Ambas operaciones se confirman juntas.
      await client.query('COMMIT');
      transaccionAbierta = false;

      return {
        entregaId: entrega.id,
        estado: resultado.estado
      };

    } catch (error) {
      if (transaccionAbierta) {
        await client.query('ROLLBACK').catch(() => {});
      }

      throw error;

    } finally {
      client.release();
    }
  }



  // ===================================================
  // PROCESAR COMO MÁXIMO UNA ENTREGA QA
  // ===================================================

  async function procesarUnaEntrega() {

    // Bloqueo por defecto.
    if (enabled !== 'true') {
      return { estado: 'DESHABILITADO' };
    }

    // Requiere una cuenta y notificación explícitas.
    if (!idValido(qaUserId) ||
        !idValido(qaNotificationId)) {
      throw new Error(
        'Configuración QA incompleta: no se permite enviar'
      );
    }

    const usuarioAutorizado = Number(qaUserId);
    const notificacionAutorizada = Number(qaNotificationId);

    // =================================================
    // HU-049: RECUPERAR SESIONES FIREBASE RENOVADAS
    // =================================================

    // Solo modifica entregas pendientes sin intentos.
    // Exige que la nueva sesion pertenezca al mismo
    // usuario y al mismo dispositivo fisico.
    // Nunca reactiva entregas ya procesadas.

    await pool.query(
      `
      WITH sesiones_actualizadas AS (
        SELECT DISTINCT ON (d.id)
          d.id AS entrega_id,
          anterior.id AS sesion_anterior,
          nueva.id AS sesion_nueva,

          ENCODE(
            SHA256(
              CONVERT_TO(
                nueva.fcm_registration_id,
                'UTF8'
              )
            ),
            'hex'
          ) AS nueva_huella

        FROM notificacion_entrega d

        INNER JOIN notificacion n
          ON n.id = d.fk_notificacion

        INNER JOIN device_session anterior
          ON anterior.id = d.fk_device_session
          AND anterior.fk_usuario = n.fk_usuario

        INNER JOIN device_session nueva
          ON nueva.fk_usuario = n.fk_usuario
          AND nueva.device_id = anterior.device_id

        INNER JOIN usuario u
          ON u.id = n.fk_usuario

        INNER JOIN perfil p
          ON p.fk_usuario = u.id

        WHERE n.id = $1
          AND n.fk_usuario = $2
          AND n.tipo = 'ADMINISTRATIVA'

          AND d.estado = 'PENDIENTE'
          AND d.intentos = 0

          AND nueva.id > anterior.id
          AND nueva.vigente = TRUE
          AND nueva.expira_en > NOW()

          AND NULLIF(
            BTRIM(nueva.fcm_registration_id),
            ''
          ) IS NOT NULL

          AND u.estado_cuenta = 'ACTIVO'
          AND u.is_verified = TRUE
          AND p.notificaciones_activas = TRUE

          AND (
            anterior.vigente IS DISTINCT FROM TRUE
            OR anterior.expira_en <= NOW()
            OR NULLIF(
              BTRIM(anterior.fcm_registration_id),
              ''
            ) IS NULL
          )

          AND NOT EXISTS (
            SELECT 1
            FROM notificacion_entrega otra

            WHERE otra.fk_notificacion = d.fk_notificacion
              AND otra.id <> d.id

              AND BTRIM(otra.registro_huella) =
                ENCODE(
                  SHA256(
                    CONVERT_TO(
                      nueva.fcm_registration_id,
                      'UTF8'
                    )
                  ),
                  'hex'
                )
          )

        ORDER BY d.id, nueva.id DESC
      )

      UPDATE notificacion_entrega d

      SET
        fk_device_session = s.sesion_nueva,
        registro_huella = s.nueva_huella

      FROM sesiones_actualizadas s

      WHERE d.id = s.entrega_id
        AND d.fk_device_session = s.sesion_anterior
        AND d.estado = 'PENDIENTE'
        AND d.intentos = 0

      RETURNING d.id
      `,
      [
        notificacionAutorizada,
        usuarioAutorizado
      ]
    );


    // =================================================
    // HU-049: RECUPERAR ENTREGAS INTERRUMPIDAS
    // =================================================

    // Solo se revisa la notificación QA autorizada.
    //
    // Una entrega EN_PROCESO que supere 15 minutos
    // puede haber sido aceptada por Firebase.
    //
    // Por seguridad, queda INDETERMINADA y
    // NO vuelve a la cola de reintentos.

    await pool.query(
      `
      UPDATE notificacion_entrega d

      SET
        estado = 'INDETERMINADA',
        ultimo_error = 'PROCESS_INTERRUPTED',
        proximo_intento_en = NULL

      FROM notificacion n

      WHERE n.id = d.fk_notificacion

        AND n.id = $1
        AND n.fk_usuario = $2
        AND n.tipo = 'ADMINISTRATIVA'

        AND d.estado = 'EN_PROCESO'

        AND (
          d.iniciado_en IS NULL
          OR d.iniciado_en <
            (
              CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
            ) - INTERVAL '15 minutes'
        )
      `,
      [
        notificacionAutorizada,
        usuarioAutorizado
      ]
    );


    // =================================================
    // RECLAMAR UNA ENTREGA PENDIENTE
    // =================================================

    const reclamada = await pool.query(
      `
      WITH candidata AS (
        SELECT d.id

        FROM notificacion_entrega d

        INNER JOIN notificacion n
          ON n.id = d.fk_notificacion

        WHERE n.id = $1
          AND n.fk_usuario = $2
          AND n.tipo = 'ADMINISTRATIVA'

          AND d.intentos < 3

          AND (
            d.estado = 'PENDIENTE'
            OR (
              d.estado = 'REINTENTO'
              AND d.proximo_intento_en <=
                (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
            )
          )

        ORDER BY d.id
        FOR UPDATE OF d SKIP LOCKED
        LIMIT 1
      )

      UPDATE notificacion_entrega d
      SET
        estado = 'EN_PROCESO',
        intentos = d.intentos + 1,
        iniciado_en = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'

      FROM candidata c

      WHERE d.id = c.id

      RETURNING
        d.id,
        d.intentos,
        d.registro_huella
      `,
      [notificacionAutorizada, usuarioAutorizado]
    );

    if (reclamada.rowCount === 0) {
      return { estado: 'SIN_ENTREGAS_PENDIENTES' };
    }

    const entrega = reclamada.rows[0];

    // =================================================
    // REVALIDAR DESTINATARIO Y DISPOSITIVO
    // =================================================

    const consulta = await pool.query(
      `
      SELECT
        n.id,
        n.titulo,
        n.mensaje,
        ds.fcm_registration_id AS fid,
        ds.vigente,
        (ds.expira_en > NOW()) AS sesion_valida,
        (
          u.estado_cuenta = 'ACTIVO'
          AND u.is_verified = TRUE
        ) AS cuenta_valida,

COALESCE(
  p.notificaciones_activas,
  FALSE
) AS notificaciones_activas,

-- Comprobar que conserva el rol destinatario.
EXISTS (
  SELECT 1
  FROM usuario_rol ur
  INNER JOIN rol r
    ON r.id = ur.fk_rol
  WHERE ur.fk_usuario = n.fk_usuario
    AND (
      n.audiencia = 'TODOS'
      OR r.nombre = n.audiencia
    )
) AS rol_autorizado,

-- Comprobar que el comunicado corresponde
-- a una auditoría válida y que el usuario
-- todavía pertenece al barrio seleccionado.
EXISTS (
  SELECT 1
  FROM bitacora_administrativa b
  WHERE b.modulo = 'NOTIFICACIONES'
    AND b.accion = 'ENVIO_ADMINISTRATIVO'

    AND COALESCE(
      b.detalle::jsonb -> 'notificacionIds',
      '[]'::jsonb
    ) @> jsonb_build_array(n.id)

    AND b.detalle::jsonb ->> 'audiencia'
        = n.audiencia

    AND b.detalle::jsonb ->> 'titulo'
        = n.titulo

    AND (
      b.detalle::jsonb ->> 'barrio' IS NULL
      OR p.barrio_notificaciones
         IS NOT DISTINCT FROM
         (b.detalle::jsonb ->> 'barrio')
      )
  ) AS comunicado_autorizado


      FROM notificacion_entrega d

      INNER JOIN notificacion n
        ON n.id = d.fk_notificacion

      INNER JOIN usuario u
        ON u.id = n.fk_usuario

      LEFT JOIN perfil p
        ON p.fk_usuario = u.id

      LEFT JOIN device_session ds
        ON ds.id = d.fk_device_session
        AND ds.fk_usuario = n.fk_usuario

      WHERE d.id = $1
        AND n.id = $2
        AND n.fk_usuario = $3
        AND n.tipo = 'ADMINISTRATIVA'
      `,
      [
        entrega.id,
        notificacionAutorizada,
        usuarioAutorizado
      ]
    );

    const destino = consulta.rows[0];

    const fid = destino?.fid;

    const huellaActual =
      typeof fid === 'string' && fid.trim()
        ? createHash('sha256')
            .update(fid)
            .digest('hex')
        : null;

    const dispositivoValido =
      destino &&
      destino.vigente === true &&
      destino.sesion_valida === true &&
      destino.cuenta_valida === true &&
      destino.notificaciones_activas === true &&
      destino.rol_autorizado === true &&
      destino.comunicado_autorizado === true &&
      huellaActual === entrega.registro_huella.trim();

    if (!dispositivoValido) {
      return finalizar(entrega, {
        estado: 'OMITIDA',
        error: 'DESTINATARIO_NO_DISPONIBLE'
      });
    }

    // =================================================
    // ENVIAR A FIREBASE
    // =================================================

    let resultado;

    try {
      const transportador = sender ??
        createFirebaseSender({ enabled: true });

      const mensajeId = await transportador.send({
        fid,
        notification: {
          title: destino.titulo,
          body: destino.mensaje
        },
        data: {
          type: 'ADMINISTRATIVA',
          notificationId: String(destino.id)
        },
        tag: `animap-admin-${destino.id}`
      });

      resultado = {
        estado: 'ACEPTADA_FCM',
        mensajeId,
        aceptadoEn: new Date(now()).toISOString()
      };

    } catch (error) {
      const fallo = classifyFirebaseError(error, now());

      resultado = {
        estado: fallo.indeterminate
          ? 'INDETERMINADA'
          : 'FALLIDA_PERMANENTE',
        error: fallo.code
      };

      // Reintentar únicamente errores transitorios
      // y como máximo tres intentos.
      if (fallo.transient && entrega.intentos < 3) {
        const espera = Math.max(
          fallo.retryAfterMs,
          60000 * Math.pow(2, entrega.intentos - 1) +
            Math.floor(random() * 10000)
        );

        resultado = {
          estado: 'REINTENTO',
          error: fallo.code,
          proximoIntento:
            new Date(now() + espera).toISOString()
        };
      }
    }

    // Registrar el resultado en PostgreSQL.
    return finalizar(entrega, resultado);
  }

  return {
    procesarUnaEntrega
  };
}

module.exports = {
  createAdminDeliveryWorker
};
