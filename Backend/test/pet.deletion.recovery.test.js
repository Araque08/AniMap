const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { format } = require('node:util');
const { spawnSync } = require('node:child_process');
const { tmpdir } = require('node:os');
const express = require('express');
const { BSON, ObjectId, MongoClient } = require('mongodb');

process.env.MONGO_URI = 'mongodb://127.0.0.1:9/isolated-pet-recovery';
MongoClient.prototype.connect = async () => { throw new Error('Real MongoDB access disabled'); };
const postgres = require('../src/config/postgres_db');
postgres.pool.query = async () => { throw new Error('Real PostgreSQL access disabled'); };
let current;
require('../src/config/mongo_db').getMongoDb = async () => current.mongo;
const images = require('../src/modules/pets/pets.images.repository');
const router = require('../src/modules/pets/pets.routes');
const { signAccessToken } = require('../src/utils/jwt');

const copy = value => BSON.deserialize(BSON.serialize(value), { promoteBuffers: true });
const matches = (document, filter) => Object.entries(filter).every(([key, value]) => {
  const actual = document[key];
  if (value && typeof value === 'object' && '$in' in value) {
    return value.$in.some(item => String(item) === String(actual));
  }
  return String(actual) === String(value);
});

function fixture(options = {}) {
  const originals = [1, 2, 3].map(index => ({
    _id: new ObjectId(`00000000000000000000000${index}`),
    mascotaIdPg: 7, usuarioIdPg: 3, imagen: Buffer.from(`original-content-${index}`),
    mimeType: 'image/png', esPrincipal: index === 1, estado: 'ACTIVA',
    metadata: { original: true }, createdAt: new Date('2026-10-12T12:00:00Z'),
  }));
  const stores = new Map();
  stores.set('ImagenMascota', originals.map(copy));
  const calls = { deletes: 0, released: 0, connections: 0, logs: [] };
  const mongo = {
    client: { async close() {} },
    collection(name) {
      if (!stores.has(name)) stores.set(name, []);
      const documents = () => stores.get(name);
      return {
        find(filter) { return { toArray: async () => documents().filter(doc => matches(doc, filter)).map(copy) }; },
        async findOne(filter) { const doc = documents().find(item => matches(item, filter)); return doc ? copy(doc) : null; },
        async countDocuments(filter) { return documents().filter(doc => matches(doc, filter)).length; },
        async insertOne(doc) { documents().push(copy(doc)); return { acknowledged: true }; },
        async insertMany(docs) {
          documents().push(...docs.map(copy));
          if (options.backupFailure) { documents().splice(1); throw new Error('Simulated quota failure'); }
          if (options.corruptBackup) documents().find(doc => doc.original)?.original.imagen.fill(0);
          return { acknowledged: true };
        },
        async updateOne(filter, update, config = {}) {
          if (name === 'ImagenMascota' && options.restoreFailure && String(filter._id) === String(originals[0]._id)) {
            throw new Error('Simulated restoration failure');
          }
          const doc = documents().find(item => matches(item, filter));
          if (doc && update.$set) Object.assign(doc, copy(update.$set));
          if (!doc && config.upsert) documents().push(copy({ ...filter, ...update.$setOnInsert }));
          return { matchedCount: doc ? 1 : 0, acknowledged: true };
        },
        async replaceOne(filter, original) {
          const index = documents().findIndex(item => matches(item, filter));
          if (index < 0) documents().push(copy(original)); else documents()[index] = copy(original);
        },
        async deleteMany(filter) {
          const selected = documents().filter(doc => matches(doc, filter));
          if (name === 'ImagenMascota') {
            calls.deletes++;
            if (options.deleteFailure === 'before') throw new Error('sensitive-test-value');
            if (options.deleteFailure === 'partial') {
              stores.set(name, documents().filter(doc => doc !== selected[0]));
              throw new Error('sensitive-test-value');
            }
          } else if (options.cleanupFailure) {
            stores.set(name, documents().filter(doc => doc !== selected[0]));
            throw new Error('Simulated cleanup failure');
          }
          stores.set(name, documents().filter(doc => !matches(doc, filter)));
          return { deletedCount: selected.length };
        },
        async deleteOne(filter) {
          const before = documents().length;
          stores.set(name, documents().filter(doc => !matches(doc, filter)));
          return { deletedCount: before - documents().length };
        },
      };
    },
  };
  let estado = 'ACTIVA';
  const pool = { async connect() {
    calls.connections++;
    if (options.recoveryPgUnavailable && calls.connections > 1) throw new Error('Simulated PG unavailable');
    let transactionalState = null;
    return { async query(sql, values) {
      const text = sql.trim().replace(/\s+/g, ' ');
      if (text === 'BEGIN') transactionalState = estado;
      else if (text === 'ROLLBACK') transactionalState = null;
      else if (text === 'COMMIT') {
        if (options.commitFailure && calls.connections === 1) {
          if (options.commitAcknowledgmentLost) estado = transactionalState;
          transactionalState = null;
          throw new Error('Simulated commit failure');
        }
        estado = transactionalState ?? estado; transactionalState = null;
      } else if (text.startsWith('SELECT id, estado FROM mascota')) {
        assert.deepEqual(values, [7, 3]);
        return { rowCount: 1, rows: [{ id: 7, estado: transactionalState ?? estado }] };
      } else if (text.includes('FROM reporte')) {
        return { rowCount: options.activeReport ? 1 : 0, rows: [] };
      } else if (text.startsWith('UPDATE mascota')) transactionalState = 'INACTIVA';
      else throw new Error(`Unexpected SQL: ${text}`);
      return { rowCount: 0, rows: [] };
    }, release() { calls.released++; } };
  } };
  current = { mongo, pool };
  postgres.pool.connect = pool.connect;
  const journal = () => [...stores.entries()].filter(([name]) => name !== 'ImagenMascota').flatMap(([, docs]) => docs);
  const recovery = () => require('../src/modules/pets/pets.deletion-recovery.service').createPetDeletionRecovery({
    pool, repository: images, logger: { error: (...args) => calls.logs.push(format(...args)) },
  });
  return { originals, options, stores, pool, mongo, calls, journal, recovery, estado: () => estado };
}

async function remove(f) {
  const app = express(); app.use('/api/pets', router);
  const server = app.listen(0, '127.0.0.1');
  const originalError = console.error;
  console.error = (...args) => f.calls.logs.push(format(...args));
  try {
    await once(server, 'listening');
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/pets/7`, {
      method: 'DELETE', headers: { Authorization: `Bearer ${signAccessToken({ sub: 3, role: 'USUARIO' })}` },
    });
    return { status: response.status, body: await response.json() };
  } finally { console.error = originalError; await new Promise(resolve => server.close(resolve)); }
}

test('borrado parcial seguido de error restaura IDs, bytes, metadatos y principal', async () => {
  const f = fixture({ deleteFailure: 'partial' });
  assert.equal((await remove(f)).status, 500);
  assert.equal(f.estado(), 'ACTIVA');
  assert.deepEqual(f.stores.get('ImagenMascota').sort((a,b) => String(a._id).localeCompare(String(b._id))), f.originals);
  assert.equal(f.journal().length, 0);
  assert.ok(f.calls.logs.every(log => !log.includes('sensitive-test-value')));
});

test('fallo antes de borrar no pierde fotos y limpia el respaldo verificado', async () => {
  const f = fixture({ deleteFailure: 'before' });
  assert.equal((await remove(f)).status, 500);
  assert.deepEqual(f.stores.get('ImagenMascota'), f.originals);
  assert.equal(f.journal().length, 0);
});

for (const failure of ['backupFailure', 'corruptBackup']) {
  test(`${failure}: no borra si el respaldo no está completo y verificado`, async () => {
    const f = fixture({ [failure]: true });
    assert.equal((await remove(f)).status, 500);
    assert.equal(f.calls.deletes, 0);
    assert.deepEqual(f.stores.get('ImagenMascota'), f.originals);
  });
}

test('restauración fallida conserva respaldo y una instancia nueva recupera idempotentemente', async () => {
  const f = fixture({ deleteFailure: 'partial', restoreFailure: true });
  assert.equal((await remove(f)).status, 500);
  const operation = f.journal().find(doc => doc.kind === 'operation');
  assert.ok(operation);
  assert.equal(f.journal().filter(doc => doc.kind === 'photo').length, 3);
  f.options.restoreFailure = false;
  const freshRecovery = f.recovery();
  assert.equal((await freshRecovery.recover(operation._id)).ok, true);
  assert.deepEqual(f.stores.get('ImagenMascota').sort((a,b) => String(a._id).localeCompare(String(b._id))), f.originals);
  assert.equal((await f.recovery().recover(operation._id)).ok, true);
  assert.equal(f.journal().length, 0);
});

test('operación correcta verifica INACTIVA, borra imágenes y elimina respaldos', async () => {
  const f = fixture();
  const response = await remove(f);
  assert.equal(response.status, 200);
  assert.equal(response.body.imagenesEliminadas, 3);
  assert.equal(f.estado(), 'INACTIVA');
  assert.equal(f.stores.get('ImagenMascota').length, 0);
  assert.equal(f.journal().length, 0);
  assert.equal(f.calls.connections, f.calls.released);
});

test('COMMIT fallido restaura todas las fotos desde el respaldo persistente', async () => {
  const f = fixture({ commitFailure: true });
  assert.equal((await remove(f)).status, 500);
  assert.equal(f.estado(), 'ACTIVA');
  assert.equal(f.stores.get('ImagenMascota').length, 3);
  assert.equal(f.journal().length, 0);
});

test('COMMIT confirmado sin respuesta no restaura fotos de una mascota INACTIVA', async () => {
  const f = fixture({ commitFailure: true, commitAcknowledgmentLost: true });
  assert.equal((await remove(f)).status, 500);
  assert.equal(f.estado(), 'INACTIVA');
  assert.equal(f.stores.get('ImagenMascota').length, 0);
  assert.equal(f.journal().length, 0);
});

test('reporte ACTIVO bloquea antes de respaldar o eliminar', async () => {
  const f = fixture({ activeReport: true });
  assert.equal((await remove(f)).status, 409);
  assert.equal(f.calls.deletes, 0);
  assert.equal(f.journal().length, 0);
});

test('PostgreSQL no disponible conserva respaldo sin adivinar estado', async () => {
  const f = fixture({ deleteFailure: 'partial', recoveryPgUnavailable: true });
  assert.equal((await remove(f)).status, 500);
  assert.ok(f.journal().find(doc => doc.kind === 'operation'));
  assert.equal(f.journal().filter(doc => doc.kind === 'photo').length, 3);
});

test('reintentos con recuperación pendiente no duplican respaldos ni vuelven a borrar', async () => {
  const f = fixture({ deleteFailure: 'partial', restoreFailure: true });
  await remove(f);
  const header = f.journal().find(doc => doc.kind === 'operation');
  const bytes = f.journal().filter(doc => doc.kind === 'photo')
    .reduce((sum, doc) => sum + BSON.calculateObjectSize(doc.original), 0);
  assert.equal(header.bytes, bytes);
  assert.equal((await remove(f)).status, 500);
  assert.equal(f.calls.deletes, 1);
  assert.equal(f.journal().filter(doc => doc.kind === 'operation').length, 1);
  assert.equal(f.journal().filter(doc => doc.kind === 'photo').length, 3);
});

test('limpieza interrumpida conserva cabecera y se completa sin necesitar copias ya retiradas', async () => {
  const f = fixture({ cleanupFailure: true });
  assert.equal((await remove(f)).status, 500);
  const header = f.journal().find(doc => doc.kind === 'operation');
  assert.equal(header.phase, 'RESOLVED');
  assert.equal(f.stores.get('ImagenMascota').length, 0);
  f.options.cleanupFailure = false;
  assert.equal((await f.recovery().recover(header._id)).ok, true);
  assert.equal(f.journal().length, 0);
});

test('recuperación no sobrescribe fotos cambiadas después del fallo', async () => {
  const f = fixture({ deleteFailure: 'partial', restoreFailure: true });
  await remove(f);
  const header = f.journal().find(doc => doc.kind === 'operation');
  f.stores.get('ImagenMascota')[0].metadata.changed = true;
  f.options.restoreFailure = false;
  const result = await f.recovery().recover(header._id);
  assert.equal(result.ok, false);
  assert.equal(result.code, 'PET_PHOTO_RECOVERY_CONFLICT');
  assert.equal(f.stores.get('ImagenMascota')[0].metadata.changed, true);
  assert.equal(f.journal().filter(doc => doc.kind === 'photo').length, 3);
});

test('borrado correcto no toca fotos de otra mascota/propietario', async () => {
  const f = fixture();
  const foreignPhoto = { _id: new ObjectId(), mascotaIdPg: 8, usuarioIdPg: 4,
    imagen: Buffer.from('foreign-fixture'), esPrincipal: true };
  f.stores.get('ImagenMascota').push(copy(foreignPhoto));
  assert.equal((await remove(f)).status, 200);
  assert.deepEqual(f.stores.get('ImagenMascota'), [foreignPhoto]);
});

test('recuperación de INACTIVA no borra una foto cuyo contenido cambió', async () => {
  const f = fixture({ recoveryPgUnavailable: true });
  assert.equal((await remove(f)).status, 500);
  const header = f.journal().find(doc => doc.kind === 'operation');
  const changed = copy(f.originals[0]);
  changed.metadata.changed = true;
  f.stores.get('ImagenMascota').push(changed);
  f.options.recoveryPgUnavailable = false;
  const result = await f.recovery().recover(header._id);
  assert.equal(result.ok, false);
  assert.equal(result.code, 'PET_PHOTO_RECOVERY_CONFLICT');
  assert.deepEqual(f.stores.get('ImagenMascota'), [changed]);
  assert.equal(f.journal().filter(doc => doc.kind === 'photo').length, 3);
});

test('recuperación concurrente relee el journal después de obtener el bloqueo PostgreSQL', async () => {
  const f = fixture();
  let reads = 0;
  const repository = {
    async getPetPhotoRecovery() {
      reads++;
      return reads === 1 ? { _id: 'concurrent-fixture', mascotaId: 7, usuarioId: 3, phase: 'READY' } : null;
    },
    async reconcilePetPhotos() { throw new Error('Journal already cleaned by the other operation'); },
  };
  const service = require('../src/modules/pets/pets.deletion-recovery.service').createPetDeletionRecovery({
    pool: f.pool, repository, logger: { error() {} },
  });
  const result = await service.recover('concurrent-fixture');
  assert.equal(result.ok, true);
  assert.equal(result.outcome, 'ALREADY_RESOLVED');
  assert.equal(f.calls.connections, f.calls.released);
});

test('comando de recuperación funciona en otro proceso con solo el journal persistido', async () => {
  const f = fixture({ deleteFailure: 'partial', restoreFailure: true });
  await remove(f);
  const header = f.journal().find(doc => doc.kind === 'operation');
  const repoPath = require.resolve('../src/modules/pets/pets.images.repository');
  const pgPath = require.resolve('../src/config/postgres_db');
  const mongoPath = require.resolve('../src/config/mongo_db');
  const cliPath = require.resolve('../scripts/recover-pet-deletion');
  // Separate process: no parent's repository/service objects or in-flight promises.
  // Only BSON data representing persisted collections crosses the boundary.
  const bootstrap = `
    const fs = require('node:fs'); const {BSON,ObjectId,MongoClient}=require(${JSON.stringify(require.resolve('mongodb'))});
    const copy = ${copy.toString()}; const matches = ${matches.toString()};
    let current; const images = {}; const postgres = {pool:{}};
    const assert = require('node:assert/strict');
    const journalData = BSON.deserialize(Buffer.from(fs.readFileSync(0,'utf8'),'base64'),{promoteBuffers:true}).stores;
    const fixture = ${fixture.toString()};
    const f = fixture();
    for (const [name,docs] of journalData) f.stores.set(name,docs);
    MongoClient.prototype.connect=async()=>{throw new Error('Real MongoDB access disabled');};
    require.cache[${JSON.stringify(pgPath)}]={exports:{pool:{...f.pool,end:async()=>{}}}};
    f.mongo.client.close=async()=>console.log(JSON.stringify({photos:f.stores.get('ImagenMascota').length,journal:f.journal().length}));
    require.cache[${JSON.stringify(mongoPath)}]={exports:{getMongoDb:async()=>f.mongo}};
    process.argv=[process.execPath,${JSON.stringify(cliPath)},${JSON.stringify(header._id)}];
    require(${JSON.stringify(cliPath)});
  `;
  const result = spawnSync(process.execPath, ['-e', bootstrap], {
    cwd: tmpdir(), env: { ...process.env, NODE_ENV: 'test' },
    input: BSON.serialize({ stores: [...f.stores.entries()] }).toString('base64'), encoding: 'utf8', timeout: 10000,
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /"outcome":"RESTORED"/);
  assert.match(result.stdout, /"photos":3,"journal":0/);
});
