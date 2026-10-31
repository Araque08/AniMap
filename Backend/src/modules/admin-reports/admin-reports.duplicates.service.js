

const db = require('../../config/postgres_db');

// ==========================================================
// CONFIGURACIÓN
// ==========================================================

const MAX_MINUTES = 3;
const MAX_DISTANCE_METERS = 50;
const MIN_SCORE = 70;

// ==========================================================
// CALCULAR DISTANCIA EN METROS
// ==========================================================

function calculateDistance(lat1, lon1, lat2, lon2) {
  const rad = (value) => value * Math.PI / 180;
  const earthRadius = 6371000;

  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);

  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) *
    Math.cos(rad(lat2)) *
    Math.sin(dLon / 2) ** 2;

  const safe = Math.max(0, Math.min(1, a));

  return 2 * earthRadius *
    Math.atan2(Math.sqrt(safe), Math.sqrt(1 - safe));
}

// ==========================================================
// COMPARAR DESCRIPCIONES
// ==========================================================

function normalizeText(value) {
  return String(value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function similarity(a, b) {
  const first = normalizeText(a);
  const second = normalizeText(b);

  if (!first || !second) return 0;
  if (first === second) return 1;

  const words1 = new Set(first.split(' '));
  const words2 = new Set(second.split(' '));

  const common = [...words1].filter(
    (word) => words2.has(word)
  ).length;

  const total = new Set([...words1, ...words2]).size;

  return total ? common / total : 0;
}

// ==========================================================
// ANALIZAR UNA PAREJA DE REGISTROS
// ==========================================================

function analyzePair(row, type) {
  const lat1 = Number(row.lat1);
  const lng1 = Number(row.lng1);
  const lat2 = Number(row.lat2);
  const lng2 = Number(row.lng2);

  const coordinates = [lat1, lng1, lat2, lng2];

  if (coordinates.some((value) => !Number.isFinite(value))) {
    return null;
  }

  if (
    Math.abs(lat1) > 90 ||
    Math.abs(lat2) > 90 ||
    Math.abs(lng1) > 180 ||
    Math.abs(lng2) > 180
  ) {
    return null;
  }

  const distance = calculateDistance(
    lat1, lng1, lat2, lng2
  );

  const minutes = Number(row.minutesDifference);

  if (
    !Number.isFinite(minutes) ||
    minutes > MAX_MINUTES ||
    distance > MAX_DISTANCE_METERS
  ) {
    return null;
  }

  const textSimilarity = similarity(
    row.description1,
    row.description2
  );

  const sameUser =
    Number(row.user1Id) === Number(row.user2Id);

  const linked1 =
    row.linkedReport1 === null ||
    row.linkedReport1 === undefined
      ? null
      : Number(row.linkedReport1);

  const linked2 =
    row.linkedReport2 === null ||
    row.linkedReport2 === undefined
      ? null
      : Number(row.linkedReport2);

  const sameLinkedReport =
    linked1 !== null &&
    linked2 !== null &&
    linked1 === linked2;

  // ========================================================
  // PUNTUACIÓN SEGÚN EL TIPO
  // ========================================================

  let score;

  if (type === 'REPORTE') {
    // La consulta ya exige la misma mascota.
    score =
      35 +
      25 * (1 - minutes / MAX_MINUTES) +
      20 * (1 - distance / MAX_DISTANCE_METERS) +
      15 * textSimilarity +
      (sameUser ? 5 : 0);
  } else {
    // Los avistamientos no requieren una mascota vinculada.
    score =
      35 * (1 - minutes / MAX_MINUTES) +
      35 * (1 - distance / MAX_DISTANCE_METERS) +
      20 * textSimilarity +
      (sameLinkedReport ? 5 : 0) +
      (sameUser ? 5 : 0);
  }

  score = Math.round(Math.max(0, Math.min(100, score)));

  if (score < MIN_SCORE) {
    return null;
  }

  const reasons = [
    `Diferencia de ${minutes.toFixed(2)} minutos`,
    `Distancia de ${distance.toFixed(1)} metros`,
    `Similitud de descripción: ${Math.round(textSimilarity * 100)}%`,
  ];

  if (type === 'REPORTE') {
    reasons.unshift('Misma mascota registrada');
  }

  if (sameLinkedReport) {
    reasons.push('Mismo reporte de pérdida vinculado');
  }

  if (sameUser) {
    reasons.push('Mismo usuario creador');
  }

  return {
    tipo: type,

    report1Id: Number(row.id1),
    report2Id: Number(row.id2),

    mascotaId: row.petId == null
      ? null
      : Number(row.petId),

    mascotaNombre: row.petName || 'Sin mascota vinculada',

    usuario1Id: Number(row.user1Id),
    usuario2Id: Number(row.user2Id),

    reporteVinculado1: linked1,
    reporteVinculado2: linked2,

    creadoEn1: row.created1,
    creadoEn2: row.created2,

    descripcion1: row.description1,
    descripcion2: row.description2,

    ubicacion1: {
      lat: lat1,
      lng: lng1,
    },

    ubicacion2: {
      lat: lat2,
      lng: lng2,
    },

    diferenciaMinutos: Number(minutes.toFixed(2)),
    distanciaMetros: Number(distance.toFixed(1)),

    similitudDescripcion:
      Math.round(textSimilarity * 100),

    mismoUsuario: sameUser,

    coincidencia: score,
    prioridad: score >= 85 ? 'ALTA' : 'MEDIA',

    // Estado provisional, todavía no persistido.
    estadoRevision: 'PENDIENTE',

    motivos: reasons,
  };
}

// ==========================================================
// SERVICIO
// ==========================================================

function createDuplicateReportsService(pool = db.pool) {

    
  // ========================================================
  // VALIDAR DOS AVISTAMIENTOS EN UNA TRANSACCIÓN
  // ========================================================

  async function validateSightingPair(
    client,
    firstId,
    secondId
  ) {
    const ids = [firstId, secondId].map(Number).sort(
      (a, b) => a - b
    );

    if (
      ids.some((id) => !Number.isSafeInteger(id) || id <= 0) ||
      ids[0] === ids[1]
    ) {
      return null;
    }

    const result = await client.query(
      `
        SELECT
          a1.id AS "id1",
          a2.id AS "id2",

          a1.fk_usuario AS "user1Id",
          a2.fk_usuario AS "user2Id",

          a1.fk_reporte_perdida AS "linkedReport1",
          a2.fk_reporte_perdida AS "linkedReport2",

          a1.descripcion AS "description1",
          a2.descripcion AS "description2",

          a1.fecha_hora AS "created1",
          a2.fecha_hora AS "created2",

          u1.lat AS "lat1",
          u1.lng AS "lng1",
          u2.lat AS "lat2",
          u2.lng AS "lng2",

          NULL::integer AS "petId",
          NULL::text AS "petName",

          ABS(
            EXTRACT(EPOCH FROM (
              a1.fecha_hora - a2.fecha_hora
            ))
          ) / 60.0 AS "minutesDifference"

        FROM avistamiento a1

        INNER JOIN avistamiento a2
          ON a2.id = $2

        INNER JOIN ubicacion u1
          ON u1.fk_avistamiento = a1.id

        INNER JOIN ubicacion u2
          ON u2.fk_avistamiento = a2.id

        WHERE a1.id = $1
          AND a1.estado IS DISTINCT FROM 'ELIMINADO'
          AND a2.estado IS DISTINCT FROM 'ELIMINADO'
          AND ABS(
            EXTRACT(EPOCH FROM (
              a1.fecha_hora - a2.fecha_hora
            ))
          ) <= $3
      `,
      [ids[0], ids[1], MAX_MINUTES * 60]
    );

    if (result.rowCount !== 1) {
      return null;
    }

    return analyzePair(result.rows[0], 'AVISTAMIENTO');
  }


  // ========================================================
  // DETECTAR REPORTES DE PÉRDIDA SIMILARES
  // ========================================================

  async function findLostReportDuplicates() {
    const result = await pool.query(
      `
        SELECT
          r1.id AS "id1",
          r2.id AS "id2",

          r1.fk_mascota AS "petId",
          m.nombre AS "petName",

          r1.fk_usuario AS "user1Id",
          r2.fk_usuario AS "user2Id",

          r1.descripcion AS "description1",
          r2.descripcion AS "description2",

          r1.creado_en AS "created1",
          r2.creado_en AS "created2",

          u1.lat AS "lat1",
          u1.lng AS "lng1",
          u2.lat AS "lat2",
          u2.lng AS "lng2",

          NULL::integer AS "linkedReport1",
          NULL::integer AS "linkedReport2",

          ABS(
            EXTRACT(
              EPOCH FROM (r1.creado_en - r2.creado_en)
            )
          ) / 60.0 AS "minutesDifference"

        FROM reporte r1

        INNER JOIN reporte r2
          ON r1.fk_mascota = r2.fk_mascota
          AND r1.id < r2.id

        INNER JOIN mascota m
          ON m.id = r1.fk_mascota

        INNER JOIN ubicacion u1
          ON u1.fk_reporte = r1.id

        INNER JOIN ubicacion u2
          ON u2.fk_reporte = r2.id

        WHERE
          ABS(
            EXTRACT(
              EPOCH FROM (r1.creado_en - r2.creado_en)
            )
          ) <= $1

        ORDER BY r2.creado_en DESC
      `,
      [MAX_MINUTES * 60]
    );

    return result.rows
      .map((row) => analyzePair(row, 'REPORTE'))
      .filter(Boolean);
  }

  // ========================================================
  // DETECTAR AVISTAMIENTOS SIMILARES
  // ========================================================

  async function findSightingDuplicates() {
    const result = await pool.query(
      `
        SELECT
          a1.id AS "id1",
          a2.id AS "id2",

          a1.fk_usuario AS "user1Id",
          a2.fk_usuario AS "user2Id",

          a1.fk_reporte_perdida AS "linkedReport1",
          a2.fk_reporte_perdida AS "linkedReport2",

          a1.descripcion AS "description1",
          a2.descripcion AS "description2",

          a1.fecha_hora AS "created1",
          a2.fecha_hora AS "created2",

          u1.lat AS "lat1",
          u1.lng AS "lng1",
          u2.lat AS "lat2",
          u2.lng AS "lng2",

          CASE
            WHEN a1.fk_reporte_perdida =
                 a2.fk_reporte_perdida
            THEN m.id
            ELSE NULL
          END AS "petId",

          CASE
            WHEN a1.fk_reporte_perdida =
                 a2.fk_reporte_perdida
            THEN m.nombre
            ELSE NULL
          END AS "petName",

          ABS(
            EXTRACT(
              EPOCH FROM (a1.fecha_hora - a2.fecha_hora)
            )
          ) / 60.0 AS "minutesDifference"

        FROM avistamiento a1

        INNER JOIN avistamiento a2
          ON a1.id < a2.id

        INNER JOIN ubicacion u1
          ON u1.fk_avistamiento = a1.id

        INNER JOIN ubicacion u2
          ON u2.fk_avistamiento = a2.id

        LEFT JOIN reporte r
          ON r.id = a1.fk_reporte_perdida
          AND r.id = a2.fk_reporte_perdida

        LEFT JOIN mascota m
          ON m.id = r.fk_mascota

        
        WHERE
        a1.estado IS DISTINCT FROM 'ELIMINADO'
        AND a2.estado IS DISTINCT FROM 'ELIMINADO'
        AND ABS(
            EXTRACT(
            EPOCH FROM (a1.fecha_hora - a2.fecha_hora)
            )
        ) <= $1


        ORDER BY a2.fecha_hora DESC
      `,
      [MAX_MINUTES * 60]
    );

    return result.rows
      .map((row) => analyzePair(row, 'AVISTAMIENTO'))
      .filter(Boolean);
  }

  // ========================================================
  // UNIFICAR RESULTADOS
  // ========================================================

  async function findPossibleDuplicates() {
    const [lostReports, sightings] = await Promise.all([
      findLostReportDuplicates(),
      findSightingDuplicates(),
    ]);

    const duplicates = [
      ...lostReports,
      ...sightings,
    ];

    duplicates.sort(
      (a, b) => b.coincidencia - a.coincidencia
    );

    return {
      total: duplicates.length,

      prioridadAlta: duplicates.filter(
        (item) => item.prioridad === 'ALTA'
      ).length,

      prioridadMedia: duplicates.filter(
        (item) => item.prioridad === 'MEDIA'
      ).length,

      totalReportes: lostReports.length,
      totalAvistamientos: sightings.length,

      duplicados: duplicates,
    };
  }

  return {
  findPossibleDuplicates,
  findLostReportDuplicates,
  findSightingDuplicates,
  validateSightingPair,
};
}

module.exports = {
  createDuplicateReportsService,
  duplicateReportsService: createDuplicateReportsService(),
};

