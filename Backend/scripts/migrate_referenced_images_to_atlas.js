/*
 * Copies only MongoDB image documents that are currently referenced by
 * PostgreSQL. The local source is never modified and Atlas documents are
 * never overwritten.
 *
 * Usage:
 *   node scripts/migrate_referenced_images_to_atlas.js --dry-run
 *   node scripts/migrate_referenced_images_to_atlas.js --apply
 */
require('dotenv').config({ quiet: true });

const crypto = require('crypto');
const { MongoClient, ObjectId } = require('mongodb');
const { Pool } = require('pg');

const SOURCE_URI = 'mongodb://127.0.0.1:27017';
const DATABASE_NAME = process.env.MONGO_DB_NAME || 'animap';
const TARGET_URI = process.env.MONGO_URI;

const COLLECTIONS = [
  {
    name: 'ImagenMascota',
    referencesSql: `
      SELECT DISTINCT fm.storage_ref
      FROM foto_mascota fm
      INNER JOIN mascota m ON m.id = fm.fk_mascota
      WHERE fm.storage_ref IS NOT NULL
    `,
  },
  {
    name: 'ImagenPerfil',
    referencesSql: `
      SELECT DISTINCT p.foto_storage_ref AS storage_ref
      FROM perfil p
      INNER JOIN usuario u ON u.id = p.fk_usuario
      WHERE p.foto_storage_ref IS NOT NULL
    `,
  },
  {
    name: 'ImagenAvistamiento',
    referencesSql: `
      SELECT DISTINCT fa.storage_ref
      FROM foto_avistamiento fa
      INNER JOIN avistamiento a ON a.id = fa.fk_avistamiento
      WHERE fa.storage_ref IS NOT NULL
    `,
  },
];

function parseMode(argv) {
  const dryRun = argv.includes('--dry-run');
  const apply = argv.includes('--apply');
  if (dryRun === apply) {
    throw new Error('Use exactamente uno de --dry-run o --apply');
  }
  return apply ? 'apply' : 'dry-run';
}

function assertSafeTarget() {
  if (!TARGET_URI) throw new Error('MONGO_URI no está configurado');
  let hostname;
  try {
    hostname = new URL(TARGET_URI).hostname.toLowerCase();
  } catch (_) {
    throw new Error('MONGO_URI no tiene un formato válido');
  }
  if (['127.0.0.1', 'localhost', '::1'].includes(hostname)) {
    throw new Error('El destino configurado no es remoto');
  }
}

function asBuffer(value) {
  if (!value) return null;
  if (Buffer.isBuffer(value)) return value;
  if (Buffer.isBuffer(value.buffer)) return value.buffer;
  if (typeof value.value === 'function') {
    const unwrapped = value.value(true);
    if (Buffer.isBuffer(unwrapped)) return unwrapped;
  }
  return null;
}

function fingerprint(document) {
  const payload = asBuffer(document?.imagen) || asBuffer(document?.buffer);
  if (!payload) return null;
  return {
    size: payload.length,
    mimeType: document.mimeType || null,
    sha256: crypto.createHash('sha256').update(payload).digest('hex'),
  };
}

function comparableMetadata(document) {
  const keys = [
    'storageRef',
    'usuarioIdPg',
    'mascotaIdPg',
    'avistamientoIdPg',
    'nombreArchivo',
    'mimeType',
    'extension',
    'tamanoBytes',
    'esPrincipal',
    'estado',
  ];
  return Object.fromEntries(
    keys.map((key) => [key, document?.[key] ?? null])
  );
}

function sameImage(left, right) {
  const a = fingerprint(left);
  const b = fingerprint(right);
  return Boolean(
    a && b &&
    a.size === b.size &&
    a.mimeType === b.mimeType &&
    a.sha256 === b.sha256 &&
    JSON.stringify(comparableMetadata(left)) ===
      JSON.stringify(comparableMetadata(right))
  );
}

function referenceFilter(storageRef) {
  const alternatives = [{ storageRef }];
  if (ObjectId.isValid(storageRef)) {
    alternatives.unshift({ _id: new ObjectId(storageRef) });
  }
  return alternatives.length === 1 ? alternatives[0] : { $or: alternatives };
}

function emptyStats(referenced) {
  return {
    referencedPostgreSQL: referenced,
    foundLocal: 0,
    alreadyAtlas: 0,
    missingAtlas: 0,
    missingLocal: 0,
    conflicts: 0,
    copied: 0,
    verified: 0,
  };
}

async function inspectCollection({ definition, pg, sourceDb, targetDb, mode }) {
  const result = await pg.query(definition.referencesSql);
  const references = result.rows.map((row) => String(row.storage_ref));
  const stats = emptyStats(references.length);
  const pending = [];

  for (const storageRef of references) {
    const filter = referenceFilter(storageRef);
    const [source, target] = await Promise.all([
      sourceDb.collection(definition.name).findOne(filter),
      targetDb.collection(definition.name).findOne(filter),
    ]);

    if (source) stats.foundLocal += 1;
    if (target) {
      if (source && !sameImage(source, target)) stats.conflicts += 1;
      else stats.alreadyAtlas += 1;
      continue;
    }

    stats.missingAtlas += 1;
    if (!source) {
      stats.missingLocal += 1;
      continue;
    }
    pending.push(source);
  }

  if (mode === 'apply' && stats.conflicts === 0 && stats.missingLocal === 0) {
    for (const source of pending) {
      await targetDb.collection(definition.name).insertOne(source);
      stats.copied += 1;
      const copied = await targetDb.collection(definition.name).findOne({ _id: source._id });
      if (copied && sameImage(source, copied)) stats.verified += 1;
    }
  }

  return stats;
}

async function main() {
  const mode = parseMode(process.argv.slice(2));
  assertSafeTarget();

  const pg = new Pool({
    host: process.env.DB_HOST || '127.0.0.1',
    port: Number(process.env.DB_PORT || 15432),
    database: process.env.DB_NAME || 'animap',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD,
    ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
  });
  const sourceClient = new MongoClient(SOURCE_URI);
  const targetClient = new MongoClient(TARGET_URI);

  try {
    await Promise.all([sourceClient.connect(), targetClient.connect()]);
    const sourceDb = sourceClient.db(DATABASE_NAME);
    const targetDb = targetClient.db(DATABASE_NAME);
    const summary = {};

    for (const definition of COLLECTIONS) {
      summary[definition.name] = await inspectCollection({
        definition,
        pg,
        sourceDb,
        targetDb,
        mode,
      });
    }

    const blocked = Object.values(summary).some(
      (stats) => stats.conflicts > 0 || stats.missingLocal > 0
    );
    const verificationFailed = mode === 'apply' && Object.values(summary).some(
      (stats) => stats.copied !== stats.verified
    );

    process.stdout.write(`${JSON.stringify({ mode, blocked, verificationFailed, collections: summary }, null, 2)}\n`);
    if (blocked || verificationFailed) process.exitCode = 2;
  } finally {
    await Promise.allSettled([pg.end(), sourceClient.close(), targetClient.close()]);
  }
}

main().catch((error) => {
  let message = String(error?.message || 'Error no identificado');
  for (const secret of [TARGET_URI, process.env.DB_PASSWORD]) {
    if (secret) message = message.split(secret).join('[REDACTED]');
  }
  process.stderr.write(`Migración abortada de forma segura: ${message}\n`);
  process.exitCode = 1;
});
