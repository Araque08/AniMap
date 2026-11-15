const { randomUUID } = require('node:crypto');
const { ObjectId, Binary } = require('mongodb');
const postgres = require('../../config/postgres_db');
const { createRecognitionQaScope } = require('./recognition.qa');

const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const SAFE_ERRORS = new Set(['ANALYSIS_FAILED', 'PHOTO_UNAVAILABLE', 'RECOGNITION_UNAVAILABLE',
  'RECOGNITION_TIMEOUT', 'ANALYSIS_TIMEOUT', 'PROCESS_INTERRUPTED', 'MATCH_PHOTO_UNAVAILABLE',
  'INVALID_RECOGNITION_IMAGE', 'RECOGNITION_BUSY', 'MATCH_ANALYSIS_EXHAUSTED']);
const JOB_COLUMNS = `fk_avistamiento AS "sightingId", fk_usuario AS "userId", solicitud_id AS "requestId",
  huella AS fingerprint, compartir_contacto AS "shareContact", intentos AS attempts, reclamo_id AS "claimId"`;

function createMatchRepository({ pool = postgres.pool,
  mongo = () => require('../../config/mongo_db').getMongoDb(), qaScope } = {}) {
  const qa = createRecognitionQaScope(qaScope);
  async function transaction(callback) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const result = await callback(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }

  async function enqueue(client, { sightingId, userId, requestId, fingerprint, shareContact }) {
    qa.assertAuthor(userId);
    const filter = qa.sightingFilter('a', 6);
    const result = await client.query(`INSERT INTO reconocimiento_publicacion
      (fk_avistamiento,fk_usuario,solicitud_id,huella,compartir_contacto)
      SELECT a.id,a.fk_usuario,$3,$4,$5 FROM avistamiento a
      WHERE a.id=$1 AND a.fk_usuario=$2 AND a.estado IS DISTINCT FROM 'ELIMINADO' ${filter.text}
      RETURNING ${JOB_COLUMNS}`, [sightingId, userId, requestId, fingerprint, shareContact === true, ...filter.values]);
    if (qa.enabled && !result.rows[0]) throw Object.assign(new Error('Publicación fuera del alcance QA.'),
      { code: 'RECOGNITION_QA_SCOPE_FORBIDDEN', statusCode: 503 });
    return result.rows[0] || null;
  }

  async function findRequest(client, userId, requestId) {
    qa.assertAuthor(userId);
    const filter = qa.jobFilter('j', 3);
    const result = await client.query(`SELECT ${JOB_COLUMNS} FROM reconocimiento_publicacion j
      WHERE fk_usuario=$1 AND solicitud_id=$2 ${filter.text}`, [userId, requestId, ...filter.values]);
    return result.rows[0] || null;
  }

  async function claim() {
    const filter = qa.jobFilter('j', 2);
    const claimId = randomUUID();
    const result = await pool.query(`WITH candidate AS (
      SELECT fk_avistamiento, (intentos >= 3) AS exhausted FROM reconocimiento_publicacion j
      WHERE ((estado IN ('PENDIENTE','REINTENTO') AND intentos < 3
        AND proximo_intento_en <= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
        OR (estado='EN_PROCESO' AND reclamado_en < (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '15 minutes'))
      ${filter.text}
      ORDER BY fk_avistamiento FOR UPDATE SKIP LOCKED LIMIT 1
    ) UPDATE reconocimiento_publicacion j SET estado='EN_PROCESO',
      intentos=LEAST(j.intentos+1,3), reclamo_id=$1,
      reclamado_en=CURRENT_TIMESTAMP AT TIME ZONE 'UTC', proximo_intento_en=NULL
      FROM candidate c WHERE j.fk_avistamiento=c.fk_avistamiento
      RETURNING j.fk_avistamiento AS "sightingId", j.fk_usuario AS "userId",
        j.solicitud_id AS "requestId", j.huella AS fingerprint,
        j.compartir_contacto AS "shareContact", j.intentos AS attempts,
        j.reclamo_id AS "claimId", c.exhausted`, [claimId, ...filter.values]);
    return result.rows[0] || null;
  }

  async function isCurrent(client, job) {
    qa.assertAuthor(job.userId);
    const filter = qa.jobFilter('j', 3);
    const result = await client.query(`SELECT 1 FROM reconocimiento_publicacion j
      WHERE fk_avistamiento=$1 AND reclamo_id=$2 AND estado='EN_PROCESO' ${filter.text}
      FOR UPDATE`, [job.sightingId, job.claimId, ...filter.values]);
    return result.rowCount > 0;
  }

  async function photoRow(queryable, sightingId, userId) {
    qa.assertAuthor(userId);
    const filter = qa.sightingFilter('a', 3);
    const result = await queryable.query(`SELECT f.storage_ref AS "photoId", a.id AS "sightingId", a.fk_usuario AS "userId"
      FROM foto_avistamiento f JOIN avistamiento a ON a.id=f.fk_avistamiento
      WHERE a.id=$1 AND a.fk_usuario=$2 AND a.estado IS DISTINCT FROM 'ELIMINADO' ${filter.text}
      ORDER BY f.id LIMIT 1`, [sightingId, userId, ...filter.values]);
    return result.rows[0] || null;
  }

  async function readPhoto(row) {
    if (!row || !/^[0-9a-f]{24}$/i.test(row.photoId || '')) return null;
    const db = await mongo();
    const document = await db.collection('ImagenAvistamiento').findOne({
      _id: new ObjectId(row.photoId), avistamientoIdPg: Number(row.sightingId), usuarioIdPg: Number(row.userId),
    }, { maxTimeMS: 5000, projection: { imagen: 1, buffer: 1, mimeType: 1 } });
    const content = document?.imagen ?? document?.buffer;
    const buffer = Buffer.isBuffer(content) ? content : content instanceof Binary ? Buffer.from(content.value()) : null;
    if (!buffer?.length || buffer.length > MAX_PHOTO_BYTES) return null;
    const mimeType = document.mimeType;
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(mimeType)) return null;
    return { buffer, mimeType };
  }

  async function photo(job) {
    return (await readPhoto(await photoRow(pool, job.sightingId, job.userId)))?.buffer || null;
  }

  async function candidate(client, sightingId, reportId, photoId) {
    qa.assertReady();
    if (qa.enabled && Number(reportId) !== qa.reportId) return null;
    const filter = qa.sightingFilter('a', 4);
    // SHARE (rather than KEY SHARE) prevents concurrent report/pet state updates
    // until the enclosing transaction commits the evidence and its intent.
    // Outer-joined optional preference rows cannot be locked in the main SELECT.
    // Lock existing rows first; the following statement reads their latest state.
    await client.query(`SELECT p.fk_usuario FROM perfil p JOIN reporte r ON r.fk_usuario=p.fk_usuario
      WHERE r.id=$1 FOR SHARE OF p`, [reportId]);
    await client.query(`SELECT p.fk_usuario FROM preferencia_notificacion p JOIN reporte r ON r.fk_usuario=p.fk_usuario
      WHERE r.id=$1 FOR SHARE OF p`, [reportId]);
    const result = await client.query(`SELECT a.id AS "sightingId", a.fk_usuario AS "authorId",
      r.id AS "reportId", r.fk_usuario AS "ownerId", r.estado AS "reportState",
      m.estado AS "petState", e.nombre AS species,
      u.estado_cuenta='ACTIVO' AS "ownerActive", u.is_verified AS "ownerVerified",
      COALESCE(p.notificaciones_activas,FALSE) AS "notificationsEnabled",
      pn.especie_filtro AS "speciesFilter", pn.tipo_evento AS "eventFilter",
      COALESCE(pn.solo_mi_zona,FALSE) AS "onlyMyZone", COALESCE(pn.radio_km,2) AS "radiusKm",
      ur.lat AS "lostLat", ur.lng AS "lostLng", ua.lat, ua.lng,
      fm.id AS "photoMetadataId", fm.storage_ref AS "photoId", fa.id AS "sightingPhotoId",
      j.compartir_contacto AS "shareContact"
      FROM avistamiento a JOIN reconocimiento_publicacion j ON j.fk_avistamiento=a.id AND j.fk_usuario=a.fk_usuario
      JOIN foto_avistamiento fa ON fa.fk_avistamiento=a.id
      JOIN reporte r ON r.id=$2 AND r.estado='ACTIVO'
      JOIN mascota m ON m.id=r.fk_mascota AND m.fk_usuario=r.fk_usuario AND m.estado='PERDIDA'
      JOIN foto_mascota fm ON fm.fk_mascota=m.id AND fm.storage_ref=$3
      JOIN especie e ON e.id=m.fk_especie JOIN usuario u ON u.id=r.fk_usuario
      LEFT JOIN perfil p ON p.fk_usuario=u.id LEFT JOIN preferencia_notificacion pn ON pn.fk_usuario=u.id
      LEFT JOIN ubicacion ur ON ur.fk_reporte=r.id LEFT JOIN ubicacion ua ON ua.fk_avistamiento=a.id
      WHERE a.id=$1 AND a.estado IS DISTINCT FROM 'ELIMINADO' ${filter.text}
      ORDER BY fa.id,fm.id LIMIT 1 FOR SHARE OF a,r,m,fm,fa,u`, [sightingId, reportId, photoId, ...filter.values]);
    return result.rows[0] || null;
  }

  async function saveMatch(client, event, { similarity, threshold, model, notificationId = null }) {
    if (!Number.isFinite(similarity) || similarity < 0 || similarity > 1
      || !Number.isFinite(threshold) || threshold < 0 || threshold > 1) throw new TypeError('Invalid match score');
    const result = await client.query(`INSERT INTO coincidencia_reconocimiento
      (fk_foto_avistamiento,fk_foto_mascota,fk_reporte,fk_usuario,fk_notificacion,similitud,umbral_usado,modelo,creado_en)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
      ON CONFLICT(fk_foto_avistamiento,fk_reporte,fk_usuario)
      WHERE fk_usuario IS NOT NULL AND fk_reporte IS NOT NULL DO UPDATE
      SET fk_notificacion=COALESCE(coincidencia_reconocimiento.fk_notificacion,EXCLUDED.fk_notificacion)
      RETURNING id`, [event.sightingPhotoId, event.photoMetadataId, event.reportId, event.ownerId,
      notificationId, similarity * 100, threshold * 100, String(model).slice(0, 120)]);
    return result.rows[0].id;
  }

  async function complete(client, job) {
    qa.assertAuthor(job.userId);
    const filter = qa.jobFilter('j', 3);
    const result = await client.query(`UPDATE reconocimiento_publicacion j SET estado='COMPLETADA',
      proximo_intento_en=NULL, reclamo_id=NULL, reclamado_en=NULL, ultimo_error=NULL
      WHERE fk_avistamiento=$1 AND reclamo_id=$2 AND estado='EN_PROCESO' ${filter.text}`, [job.sightingId, job.claimId, ...filter.values]);
    return result.rowCount > 0;
  }

  async function fail(client, job, code, { permanent = false } = {}) {
    qa.assertAuthor(job.userId);
    const filter = qa.jobFilter('j', 5);
    const result = await client.query(`UPDATE reconocimiento_publicacion j SET
      estado=CASE WHEN intentos>=3 OR $4 THEN 'FALLIDA' ELSE 'REINTENTO' END,
      proximo_intento_en=CASE WHEN intentos>=3 OR $4 THEN NULL
        ELSE (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') + INTERVAL '1 minute' * power(2,intentos-1) END,
      ultimo_error=$3, reclamo_id=NULL, reclamado_en=NULL
      WHERE fk_avistamiento=$1 AND reclamo_id=$2 AND estado='EN_PROCESO' ${filter.text} RETURNING estado`,
    [job.sightingId, job.claimId, SAFE_ERRORS.has(code) ? code : 'ANALYSIS_FAILED', permanent, ...filter.values]);
    return result.rows[0] ? result.rows[0].estado === 'FALLIDA' : null;
  }
  async function retry(job, code) { return transaction(client => fail(client, job, code)); }

  async function loadNotification(queryable, notification) {
    const row = (await queryable.query(`SELECT c.id AS "matchId", c.similitud AS similarity,
      c.fk_reporte AS "reportId", c.fk_usuario AS "ownerId", f.fk_avistamiento AS "sightingId"
      FROM coincidencia_reconocimiento c JOIN foto_avistamiento f ON f.id=c.fk_foto_avistamiento
      WHERE c.fk_notificacion=$1 AND c.fk_usuario=$2`, [notification.id, notification.ownerId])).rows[0];
    if (!row) return null;
    const result = await queryable.query(`SELECT a.id AS "sightingId", a.fk_usuario AS "authorId",
      r.id AS "reportId", r.fk_usuario AS "ownerId", r.estado AS "reportState", m.estado AS "petState",
      e.nombre AS species, u.estado_cuenta='ACTIVO' AS "ownerActive", u.is_verified AS "ownerVerified",
      COALESCE(p.notificaciones_activas,FALSE) AS "notificationsEnabled",
      pn.especie_filtro AS "speciesFilter", pn.tipo_evento AS "eventFilter",
      COALESCE(pn.solo_mi_zona,FALSE) AS "onlyMyZone", COALESCE(pn.radio_km,2) AS "radiusKm",
      ur.lat AS "lostLat", ur.lng AS "lostLng", ua.lat,ua.lng
      FROM avistamiento a JOIN reporte r ON r.id=$2 AND r.fk_usuario=$3
      JOIN mascota m ON m.id=r.fk_mascota AND m.fk_usuario=r.fk_usuario
      JOIN especie e ON e.id=m.fk_especie JOIN usuario u ON u.id=r.fk_usuario
      LEFT JOIN perfil p ON p.fk_usuario=u.id LEFT JOIN preferencia_notificacion pn ON pn.fk_usuario=u.id
      LEFT JOIN ubicacion ur ON ur.fk_reporte=r.id LEFT JOIN ubicacion ua ON ua.fk_avistamiento=a.id
      WHERE a.id=$1 AND a.estado IS DISTINCT FROM 'ELIMINADO'`, [row.sightingId, row.reportId, row.ownerId]);
    return result.rows[0] ? { ...result.rows[0], matchId: row.matchId, similarity: Number(row.similarity) / 100 } : null;
  }

  async function history(ownerId, id, before) {
    const result = await pool.query(`SELECT c.id,c.fk_reporte AS "reportId", a.id AS "sightingId",
      c.similitud,c.umbral_usado,c.modelo,
      to_char(c.creado_en, 'YYYY-MM-DD"T"HH24:MI:SS.MS') || 'Z' AS "createdAt",
      to_char(a.fecha_hora, 'YYYY-MM-DD"T"HH24:MI:SS.MS') || 'Z' AS "observedAt", n.estado_envio,
      ua.lat,ua.lng,ua.metodo,ua.direccion,
      CASE WHEN j.compartir_contacto THEN author.nombre ELSE NULL END AS reporter_label,
      CASE WHEN j.compartir_contacto THEN author.telefono ELSE NULL END AS reporter_phone,
      m.nombre AS pet_name, fa.storage_ref AS "photoId", a.fk_usuario AS "userId"
      FROM coincidencia_reconocimiento c
      JOIN foto_avistamiento fa ON fa.id=c.fk_foto_avistamiento
      JOIN avistamiento a ON a.id=fa.fk_avistamiento
      LEFT JOIN reconocimiento_publicacion j ON j.fk_avistamiento=a.id
      LEFT JOIN reporte r ON r.id=c.fk_reporte LEFT JOIN mascota m ON m.id=r.fk_mascota
      LEFT JOIN usuario author ON author.id=a.fk_usuario
      LEFT JOIN ubicacion ua ON ua.fk_avistamiento=a.id
      LEFT JOIN notificacion n ON n.id=c.fk_notificacion
      WHERE c.fk_usuario=$1 AND ($2::integer IS NULL OR c.id=$2)
        AND ($3::integer IS NULL OR c.id<$3)
        AND a.estado IS DISTINCT FROM 'ELIMINADO'
      ORDER BY c.id DESC LIMIT 50`, [ownerId, id ?? null, before ?? null]);
    return result.rows;
  }
  function present(row) {
    const reporter = { label: row.reporter_label || 'Reportante' };
    if (row.reporter_phone) reporter.phone = row.reporter_phone;
    return { id: row.id, reportId: row.reportId, sightingId: row.sightingId,
      similarity: Number(row.similitud) / 100, threshold: Number(row.umbral_usado) / 100,
      model: row.modelo, createdAt: row.createdAt, observedAt: row.observedAt,
      notificationState: row.estado_envio || 'REGISTRADA',
      photoUrl: `/api/recognition/matches/${row.id}/image`,
      location: { lat: row.lat == null ? null : Number(row.lat), lng: row.lng == null ? null : Number(row.lng),
        method: row.metodo, address: row.direccion }, reporter, pet: { name: row.pet_name } };
  }
  async function list(ownerId, before) { return (await history(ownerId, null, before)).map(present); }
  async function detail(ownerId, id) { const row = (await history(ownerId, id))[0]; return row ? present(row) : null; }
  async function image(ownerId, id) {
    const row = (await history(ownerId, id))[0];
    return row ? readPhoto(row) : null;
  }
  return { pool, enqueue, findRequest, claim, isCurrent, photo, candidate, saveMatch,
    complete, fail, retry, transaction, list, detail, image, loadNotification };
}

const createMatchesRepository = pool => createMatchRepository(pool ? { pool } : {});
module.exports = { createMatchRepository, createMatchesRepository,
  createRecognitionMatchesRepository: createMatchRepository };
