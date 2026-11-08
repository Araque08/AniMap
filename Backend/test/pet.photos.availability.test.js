const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const express = require('express');
const { ObjectId, Binary } = require('mongodb');
const db = require('../src/config/postgres_db');
const mongo = require('../src/config/mongo_db');
const id = n => n.toString(16).padStart(24, '0');
const png = n => Buffer.from([137,80,78,71,13,10,26,10,n]);
const state = {};
const clone = d => ({ ...d, _id: new ObjectId(d._id), imagen: d.imagen instanceof Binary ? new Binary(d.imagen.value()) : Buffer.from(d.imagen) });
function matches(d, filter) {
  return Object.entries(filter).every(([key, value]) => value?.$in
    ? value.$in.some(v => String(v) === String(d[key])) : String(d[key]) === String(value));
}
const collection = {
  find(filter) { const query = { project() { return query; }, async toArray() {
    return [...state.docs.values()].filter(d => matches(d, filter)).map(clone);
  } }; return query; },
  async findOne(filter) { const d = [...state.docs.values()].find(d => matches(d, filter)); return d ? clone(d) : null; },
  async updateMany(filter, update) { for (const d of state.docs.values()) if (matches(d, filter)) Object.assign(d, update.$set); return {}; },
  async updateOne(filter, update) {
    let d = [...state.docs.values()].find(d => matches(d, filter));
    if (!d && update.$setOnInsert) { d = clone(update.$setOnInsert); state.docs.set(String(d._id), d); }
    if (d) Object.assign(d, update.$set || {});
    return { matchedCount: d ? 1 : 0 };
  },
  async deleteOne(filter) { const d = [...state.docs.values()].find(d => matches(d, filter));
    if (d) state.docs.delete(String(d._id));
    if (state.failDelete) throw Error('simulated partial delete');
    return { deletedCount: d ? 1 : 0 };
  },
  async deleteMany(filter) { for (const d of [...state.docs.values()]) if (matches(d, filter)) state.docs.delete(String(d._id)); },
  async replaceOne(filter, d) { state.docs.set(String(d._id), clone(d)); return {}; },
};
mongo.getMongoDb = async () => ({ collection: () => collection });
const repo = require('../src/modules/pets/pets.images.repository');
repo.guardarImagenesMascota = async ({ files }) => files.map((file, n) => {
  const key = id(100+n); state.docs.set(key, { _id: new ObjectId(key), mascotaIdPg: 1, usuarioIdPg: 7,
    estado: 'ACTIVA', mimeType: 'image/png', esPrincipal: false, imagen: Buffer.from(file.buffer) });
  return { id: new ObjectId(key), storageRef: key, urlPreview: `/api/pets/images/${key}` };
});
const client = { release() {}, async query(sql, p = []) {
  const q = sql.replace(/\s+/g, ' ').trim();
  if (q === 'BEGIN') { state.before = structuredClone(state.refs); return {}; }
  if (q === 'ROLLBACK') { state.refs = state.before; return {}; }
  if (q === 'COMMIT') { if (state.failCommit) throw Error('simulated commit failure'); return {}; }
  if (q.startsWith('SELECT id, estado FROM mascota')) return { rows: p[0] === 1 && p[1] === 7 ? [{ id: 1, estado: 'ACTIVA' }] : [], rowCount: p[1] === 7 ? 1 : 0 };
  if (q.startsWith('SELECT') && q.includes('FROM foto_mascota')) return { rows: structuredClone(state.refs), rowCount: state.refs.length };
  if (q.startsWith('INSERT INTO foto_mascota')) { state.refs.push({ storage_ref: p[1], es_principal: false }); return { rowCount: 1 }; }
  if (q.startsWith('UPDATE foto_mascota SET es_principal = FALSE')) { state.refs.forEach(r => { r.es_principal = false; }); return {}; }
  if (q.startsWith('UPDATE foto_mascota SET es_principal = TRUE')) { const r = state.refs.find(r => r.storage_ref === p[1]); if (r) r.es_principal = true; return { rowCount: r ? 1 : 0 }; }
  if (q.startsWith('DELETE FROM foto_mascota')) { state.refs = state.refs.filter(r => r.storage_ref !== p[1]); return {}; }
  throw Error('Unexpected isolated SQL');
} };
db.query = (...args) => client.query(...args); db.pool.connect = async () => client;
require('../test-support/auth-fixture.cjs').installAuthFixture({7:'USUARIO'});
const app = express(); app.use('/api/pets', require('../src/modules/pets/pets.routes'));
let server, url;
test.before(async () => { server = app.listen(0,'127.0.0.1'); await once(server,'listening'); url = `http://127.0.0.1:${server.address().port}`; });
test.after(async () => { await new Promise(resolve => server.close(resolve)); });
test.beforeEach(() => {
  state.refs = Array.from({length:15},(_,n)=>({storage_ref:id(n+1),es_principal:n===0}));
  state.docs = new Map(state.refs.map((r,n)=>[r.storage_ref,{_id:new ObjectId(r.storage_ref),mascotaIdPg:1,usuarioIdPg:7,
    estado:'ACTIVA',mimeType:'image/png',esPrincipal:n===0,imagen:png(n+1)}]));
  state.failCommit = false; state.failDelete = false;
});
async function save({ removed = [], file = png(99), principal = id(1) } = {}) {
  const form = new FormData(); form.set('original_image_ids', JSON.stringify(state.refs.map(r=>r.storage_ref)));
  form.set('retained_image_ids', JSON.stringify(state.refs.map(r=>r.storage_ref).filter(r=>!removed.includes(r))));
  if (principal) form.set('principal_existing_id', principal);
  else form.set('principal_new_index', '0');
  if (file) form.append('imagenes', new Blob([file],{type:'image/png'}),'new.png');
  return fetch(url+'/api/pets/1/images/batch',{method:'PUT',headers:{Authorization:`Bearer ${require('../src/utils/jwt').signAccessToken({sub:7,deviceId:'fixture-device',role:'USUARIO'})}`},body:form});
}
test('15 valid photos: adding preserves originals and the unique principal', async () => {
  assert.equal((await save()).status,200); assert.equal(state.refs.length,16);
  assert.deepEqual(state.refs.filter(r=>r.es_principal).map(r=>r.storage_ref),[id(1)]);
});
test('missing retained document is rejected without counting it or writing anything', async () => {
  state.docs.delete(id(15)); const before = structuredClone(state.refs);
  assert.equal((await save()).status,409); assert.deepEqual(state.refs,before); assert.equal(state.docs.size,14);
});

async function readImage(key = id(15)) {
  return fetch(url+'/api/pets/images/'+key, {headers:{Authorization:`Bearer ${require('../src/utils/jwt').signAccessToken({sub:7,deviceId:'fixture-device',role:'USUARIO'})}`}});
}

test('private image returns 404 for a missing document or empty binary', async () => {
  state.docs.delete(id(15)); assert.equal((await readImage()).status,404);
  state.docs.set(id(15),{...clone(state.docs.get(id(1))),_id:new ObjectId(id(15)),imagen:Buffer.alloc(0)});
  assert.equal((await readImage()).status,404);
  assert.equal((await save()).status,409);
  assert.equal(state.refs.length,15);
});

test('Binary uses actual bytes, and malformed or oversized retained content cannot count', async () => {
  const binary = new Binary(png(15)); binary.buffer = Buffer.concat([binary.buffer,Buffer.from([0,0])]);
  state.docs.get(id(15)).imagen = binary;
  assert.deepEqual(Buffer.from(await (await readImage()).arrayBuffer()),png(15));
  assert.equal((await save({file:png(15)})).status,409);
  for (const invalid of [Buffer.from('not an image'),Buffer.alloc(5*1024*1024+1)]) {
    state.docs.get(id(15)).imagen = invalid;
    assert.equal((await save()).status,409);
    assert.equal(state.refs.length,15);
  }
  state.docs.get(id(15)).imagen = png(15);
  state.docs.get(id(15)).mimeType = 'text/html';
  assert.equal((await save()).status,409);
});

test('explicit replacement of missing principal requires a valid new principal', async () => {
  state.docs.delete(id(1));
  assert.equal((await save({removed:[id(1)],principal:null})).status,200);
  assert.deepEqual(state.refs.filter(r=>r.es_principal).map(r=>r.storage_ref),[id(100)]);
  assert.equal([...state.docs.values()].filter(d=>d.esPrincipal).length,1);
});
test('explicit removal of a missing reference plus replacement succeeds, no automatic cleanup', async () => {
  state.docs.delete(id(15));
  assert.equal((await save({removed:[id(15)]})).status,200);
  assert.equal(state.refs.length,15); assert.equal(state.docs.size,15); assert.ok(state.refs.some(r=>r.storage_ref===id(100)));
});
for (const field of ['usuarioIdPg','mascotaIdPg','estado']) test(`incompatible ${field} cannot be retained or silently removed`, async () => {
  state.docs.get(id(15))[field] = field==='estado'?'INACTIVA':999;
  if (field !== 'mascotaIdPg') assert.equal((await readImage()).status,404);
  assert.equal((await save()).status,409);
  assert.equal((await save({removed:[id(15)]})).status,409);
  assert.equal(state.refs.length,15); assert.ok(state.docs.has(id(15)));
});
test('duplicates and fewer than 15 valid images are rejected before writes', async () => {
  assert.equal((await save({file:png(1)})).status,409);
  assert.equal((await save({removed:[id(15)],file:null})).status,409);
  assert.equal(state.docs.size,15);
});
test('commit failure and partial Mongo delete restore every original photo', async () => {
  for (const failure of ['failCommit','failDelete']) {
    state[failure] = true; const original = [...state.docs].map(([k,d])=>[k,Buffer.from(d.imagen)]);
    assert.equal((await save({removed:[id(15)]})).status,500);
    assert.equal(state.refs.length,15); assert.equal(state.docs.size,15);
    for (const [key,bytes] of original) assert.deepEqual(state.docs.get(key)?.imagen,bytes);
    assert.equal([...state.docs.values()].filter(d=>d.esPrincipal).length,1);
    state[failure] = false;
  }
});
