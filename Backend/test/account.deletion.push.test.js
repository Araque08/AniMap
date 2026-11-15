const test = require('node:test');
const assert = require('node:assert/strict');

function fixture(t, { failPush = false, failImages = false, validPassword = true } = {}) {
  const pg = require('../src/config/postgres_db');
  const mongoModule = require('../src/config/mongo_db');
  const hash = require('../src/utils/hash');
  const original = { connect: pg.pool.connect, mongo: mongoModule.getMongoDb, compare: hash.compareHash };
  const modulePath = require.resolve('../src/modules/profile/account-deletion.service');
  const savedModule = require.cache[modulePath];
  const state = { users: [7, 8], pushUsers: [7, 8], committed: false, released: false };
  const calls = [];
  let snapshot;
  const collections = new Map(['ImagenPerfil', 'ImagenMascota', 'ImagenAvistamiento']
    .map(name => [name, [{ _id: `${name}-7`, usuarioIdPg: 7 }, { _id: `${name}-8`, usuarioIdPg: 8 }]]));
  const client = {
    async query(sql, params = []) {
      const s = sql.replace(/\s+/g, ' ').trim(); calls.push(s);
      if (s === 'BEGIN') { snapshot = structuredClone(state); return {}; }
      if (s === 'COMMIT') { state.committed = true; return {}; }
      if (s === 'ROLLBACK') { Object.assign(state, snapshot); return {}; }
      if (s.startsWith('SELECT id, password_hash')) return { rowCount: 1, rows: [{ id: 7, password_hash: 'fixture', estado_cuenta: 'ACTIVO' }] };
      if (s.startsWith('SELECT EXISTS')) return { rows: [{ existe: false }] };
      assert.deepEqual(params, [7]);
      if (s.startsWith('DELETE FROM device_push_registration')) {
        if (failPush) throw Error('synthetic-push-failure');
        state.pushUsers = state.pushUsers.filter(id => id !== 7); return { rowCount: 1 };
      }
      if (s.startsWith('DELETE FROM usuario')) {
        // Model the FK that caused the original account-deletion failure.
        if (state.pushUsers.includes(7)) throw Error('synthetic-push-fk-restrict');
        state.users = state.users.filter(id => id !== 7); return { rowCount: 1, rows: [{ id: 7 }] };
      }
      throw Error('Unexpected isolated account query');
    },
    release() { state.released = true; },
  };
  pg.pool.connect = async () => client;
  hash.compareHash = async () => validPassword;
  mongoModule.getMongoDb = async () => ({
    command: async () => ({ ok: 1 }),
    collection(name) {
      return {
        find: filter => ({ toArray: async () => structuredClone(collections.get(name).filter(d => d.usuarioIdPg === filter.usuarioIdPg)) }),
        async deleteMany(filter) {
          if (failImages && name === 'ImagenMascota') throw Error('synthetic-image-failure');
          collections.set(name, collections.get(name).filter(d => d.usuarioIdPg !== filter.usuarioIdPg));
        },
        countDocuments: async filter => collections.get(name).filter(d => d.usuarioIdPg === filter.usuarioIdPg).length,
        async replaceOne(filter, document) {
          const docs = collections.get(name).filter(d => d._id !== filter._id);
          docs.push(structuredClone(document)); collections.set(name, docs);
        },
      };
    },
  });
  delete require.cache[modulePath];
  const { deleteOwnAccount } = require(modulePath);
  t.after(() => {
    pg.pool.connect = original.connect; mongoModule.getMongoDb = original.mongo; hash.compareHash = original.compare;
    if (savedModule) require.cache[modulePath] = savedModule; else delete require.cache[modulePath];
  });
  return { remove: () => deleteOwnAccount(7, 'isolated-fixture'), state, calls, collections };
}

test('account deletion removes its push registration and preserves other users', async t => {
  const h = fixture(t);
  assert.deepEqual(await h.remove(), { deleted: true });
  assert.deepEqual(h.state.users, [8]); assert.deepEqual(h.state.pushUsers, [8]);
  assert.equal(h.state.committed, true); assert.equal(h.state.released, true);
  for (const docs of h.collections.values()) assert.deepEqual(docs.map(d => d.usuarioIdPg), [8]);
});

test('failed push cleanup rolls back account deletion without removing images', async t => {
  const h = fixture(t, { failPush: true });
  await assert.rejects(h.remove(), { statusCode: 503, code: 'ACCOUNT_DELETION_FAILED' });
  assert.deepEqual(h.state.users, [7, 8]); assert.deepEqual(h.state.pushUsers, [7, 8]);
  assert.equal(h.state.committed, false); assert.equal(h.state.released, true);
  assert.equal(h.calls.some(sql => sql.startsWith('DELETE FROM usuario')), false);
  for (const docs of h.collections.values()) assert.equal(docs.length, 2);
});

test('MongoDB failure restores removed images and rolls back push cleanup', async t => {
  const h = fixture(t, { failImages: true });
  await assert.rejects(h.remove(), { statusCode: 503, code: 'ACCOUNT_DELETION_FAILED' });
  assert.deepEqual(h.state.users, [7, 8]); assert.deepEqual(h.state.pushUsers, [7, 8]);
  assert.equal(h.state.committed, false); assert.equal(h.state.released, true);
  for (const docs of h.collections.values()) assert.deepEqual(docs.map(d => d.usuarioIdPg).sort(), [7, 8]);
});

test('wrong password cannot remove an account or its push registrations', async t => {
  const h = fixture(t, { validPassword: false });
  await assert.rejects(h.remove(), { statusCode: 403, code: 'INVALID_PASSWORD' });
  assert.deepEqual(h.state.users, [7, 8]); assert.deepEqual(h.state.pushUsers, [7, 8]);
  assert.equal(h.calls.some(sql => sql.startsWith('DELETE')), false);
});
