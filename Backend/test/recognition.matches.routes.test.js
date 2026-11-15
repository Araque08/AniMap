const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { createRecognitionRouter } = require('../src/modules/recognition/recognition.routes');

test('historial/detalle/foto usan usuario autenticado, validan IDs y no permiten IDOR', async t => {
  const app = express();
  let owner = 7, authenticated = true;
  app.use('/api/recognition', createRecognitionRouter({
    authenticate(req, res, next) {
      if (!authenticated) return res.sendStatus(401);
      req.auth = { userId: owner }; next();
    },
    matches: {
      async list(userId, before) { assert.equal(userId, owner); return [{ id: 3, before }]; },
      async detail(userId, id) {
        if (userId !== 7 || id !== 3) throw Object.assign(new Error('Coincidencia no encontrada'), { statusCode: 404 });
        return { id, photoUrl: '/api/recognition/matches/3/image' };
      },
      async image(userId, id) {
        if (userId !== 7 || id !== 3) throw Object.assign(new Error('Fotografía no encontrada'), { statusCode: 404 });
        return { buffer: Buffer.from([255,216,255]), mimeType: 'image/jpeg' };
      },
    },
  }));
  app.use((err, req, res, next) => res.status(err.statusCode || 500).json({ ok: false }));
  const server = app.listen(0, '127.0.0.1'); await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const get = path => fetch(`http://127.0.0.1:${server.address().port}/api/recognition${path}`);
  let res = await get('/matches?before=4'); assert.equal(res.status, 200);
  assert.equal((await res.json()).data[0].before, 4);
  assert.equal((await get('/matches/3')).status, 200);
  res = await get('/matches/3/image'); assert.equal(res.status, 200);
  assert.match(res.headers.get('cache-control'), /no-store/);
  assert.deepEqual(Buffer.from(await res.arrayBuffer()), Buffer.from([255,216,255]));
  assert.equal((await get('/matches/not-an-id')).status, 400);
  assert.equal((await get('/matches?before=NaN')).status, 400);
  owner = 8; assert.equal((await get('/matches/3')).status, 404);
  assert.equal((await get('/matches/3/image')).status, 404);
  authenticated = false; assert.equal((await get('/matches')).status, 401);
});


// Mocks de PostgreSQL/MongoDB; JWT y middleware de autenticación reales.
test('privacidad HU-034: historial, detalle, fotografía y consentimiento', async t => {
  const { createMatchRepository } = require('../src/modules/recognition/recognition.matches.repository');
  const { createMatchService } = require('../src/modules/recognition/recognition.matches.service');
  const { signAccessToken } = require('../src/utils/jwt');
  const restoreAuth = require('../test-support/auth-fixture.cjs').installAuthFixture({ 7: 'USUARIO', 8: 'USUARIO' });
  t.after(restoreAuth);
  const photoId = '507f1f77bcf86cd799439011';
  const bytes = Buffer.from([255, 216, 255, 42]);
  let consent = false, deleted = false, documentPresent = true;
  let queryCount = 0, mongoCount = 0;
  const repo = createMatchRepository({
    qaScope: { enabled: false },
    pool: {
      async query(sql, values) {
        queryCount++;
        // El repositorio debe aplicar las restricciones antes de devolver filas.
        assert.match(sql, /WHERE c\.fk_usuario=\$1/);
        assert.match(sql, /\$2::integer IS NULL OR c\.id=\$2/);
        assert.match(sql, /a\.estado IS DISTINCT FROM 'ELIMINADO'/);
        assert.match(sql, /CASE WHEN j\.compartir_contacto THEN author\.nombre ELSE NULL END/);
        assert.match(sql, /CASE WHEN j\.compartir_contacto THEN author\.telefono ELSE NULL END/);
        const visible = values[0] === 7 && (values[1] == null || values[1] === 3)
          && (values[2] == null || 3 < values[2]) && !deleted;
        return { rows: visible ? [{
          id: 3, reportId: 5, sightingId: 11, userId: 8, photoId,
          similitud: 91, umbral_usado: 80, modelo: 'resnet50-imagenet1k-v2',
          createdAt: '2026-11-01T12:00:00.000Z', observedAt: '2026-11-01T11:00:00.000Z',
          lat: '4.65', lng: '-74.1', metodo: 'MAPA', direccion: 'Punto sintético',
          reporter_label: consent === true ? 'Reportante sintético' : null,
          reporter_phone: consent === true ? '3000000000' : null,
          pet_name: 'Mascota sintética',
        }] : [] };
      },
    },
    mongo: async () => ({
      collection(name) {
        assert.equal(name, 'ImagenAvistamiento');
        return {
          async findOne(filter) {
            mongoCount++;
            // No basta con conocer el ObjectId: deben coincidir las relaciones.
            assert.equal(filter._id.toHexString(), photoId);
            assert.equal(filter.avistamientoIdPg, 11);
            assert.equal(filter.usuarioIdPg, 8);
            return documentPresent ? { imagen: bytes, mimeType: 'image/jpeg' } : null;
          },
        };
      },
    }),
  });
  const service = createMatchService({ repo, enabled: true });
  const app = express();
  app.use('/api/recognition', createRecognitionRouter({ matches: service }));
  app.use((error, req, res, next) => res.status(error.statusCode || 500).json({ ok: false, message: error.message }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = 'http://127.0.0.1:' + server.address().port + '/api/recognition';
  const headers = userId => ({ Authorization: 'Bearer ' + signAccessToken({ sub: String(userId), deviceId: 'privacy-fixture' }) });
  const get = (path, userId) => fetch(base + path, { headers: userId ? headers(userId) : {} });

  await t.test('sin autenticación o con JWT inválido: 401 en las tres rutas, sin leer fotos', async () => {
    const before = [queryCount, mongoCount];
    for (const path of ['/matches', '/matches/3', '/matches/3/image']) {
      assert.equal((await get(path)).status, 401);
      assert.equal((await fetch(base + path, { headers: { Authorization: 'Bearer invalid-fixture' } })).status, 401);
    }
    assert.deepEqual([queryCount, mongoCount], before);
  });
  await t.test('el destinatario consulta su historial, detalle y foto sin caché pública', async () => {
    const list = await get('/matches', 7);
    assert.equal(list.status, 200);
    assert.equal((await list.json()).data[0].id, 3);
    const detail = await get('/matches/3', 7);
    assert.equal(detail.status, 200);
    assert.equal((await detail.json()).data.photoUrl, '/api/recognition/matches/3/image');
    const image = await get('/matches/3/image', 7);
    assert.equal(image.status, 200);
    assert.equal(image.headers.get('cache-control'), 'private, no-store');
    assert.match(image.headers.get('content-type'), /image\/jpeg/);
    assert.deepEqual(Buffer.from(await image.arrayBuffer()), bytes);
  });
  await t.test('otro usuario no puede sustituir al destinatario mediante query o ID', async () => {
    const before = mongoCount;
    const list = await get('/matches?userId=7&ownerId=7', 8);
    assert.deepEqual((await list.json()).data, []);
    for (const path of ['/matches/3?userId=7', '/matches/3/image?ownerId=7']) {
      assert.equal((await get(path, 8)).status, 404);
    }
    assert.equal(mongoCount, before);
  });
  await t.test('un ID ajeno y uno inexistente producen el mismo 404', async () => {
    for (const suffix of ['', '/image']) {
      const foreign = await get('/matches/3' + suffix, 8);
      const missing = await get('/matches/999' + suffix, 7);
      assert.equal(foreign.status, 404);
      assert.equal(missing.status, 404);
      assert.deepEqual(await foreign.json(), await missing.json());
    }
  });
  await t.test('sin consentimiento explícito no aparecen nombre ni teléfono del autor', async () => {
    for (const value of [false, null, undefined]) {
      consent = value;
      const data = (await (await get('/matches/3', 7)).json()).data;
      assert.deepEqual(data.reporter, { label: 'Reportante' });
      assert.equal(data.photoId, undefined);
      assert.equal(data.userId, undefined);
      assert.equal(JSON.stringify(data).includes(photoId), false);
      assert.equal(JSON.stringify(data).includes('3000000000'), false);
    }
  });
  await t.test('con consentimiento solo se devuelve el contacto permitido, nunca el correo', async () => {
    consent = true;
    const data = (await (await get('/matches/3', 7)).json()).data;
    assert.deepEqual(data.reporter, { label: 'Reportante sintético', phone: '3000000000' });
    assert.equal(data.reporter.email, undefined);
  });
  await t.test('una referencia sin documento válido devuelve 404', async () => {
    documentPresent = false;
    assert.equal((await get('/matches/3/image', 7)).status, 404);
    documentPresent = true;
  });
  await t.test('un avistamiento eliminado deja de aparecer en el historial y su ruta privada', async () => {
    deleted = true;
    assert.deepEqual((await (await get('/matches', 7)).json()).data, []);
    assert.equal((await get('/matches/3', 7)).status, 404);
    assert.equal((await get('/matches/3/image', 7)).status, 404);
    deleted = false;
  });
});

test('una foto publicada de avistamiento es pública; no abre referencias privadas o eliminadas', async () => {
  const { createSightingsService } = require('../src/modules/sightings/sightings.service');
  const photoId = '507f1f77bcf86cd799439012';
  let visible = true, mongoReads = 0;
  const service = createSightingsService({
    async query(sql, values) {
      assert.match(sql, /FROM foto_avistamiento fa/);
      assert.match(sql, /a\.estado IS DISTINCT FROM 'ELIMINADO'/);
      assert.deepEqual(values, [photoId]);
      return visible ? { rowCount: 1, rows: [{ id: 1 }] } : { rowCount: 0, rows: [] };
    },
  }, {
    async findPublicSightingImage(id) {
      mongoReads++;
      assert.equal(id, photoId);
      return { imagen: Buffer.from([255, 216, 255]), mimeType: 'image/jpeg' };
    },
  });
  assert.equal((await service.getPublicImage(photoId)).mimeType, 'image/jpeg');
  visible = false;
  await assert.rejects(service.getPublicImage(photoId), error => error.statusCode === 404);
  assert.equal(mongoReads, 1);
});


test('cambiar la URL pública no permite descargar una foto privada de mascota', async t => {
  const db = require('../src/config/postgres_db');
  const mongo = require('../src/config/mongo_db');
  const sightingImages = require('../src/modules/sightings/sightings.images.repository');
  const oldQuery = db.query, oldPoolQuery = db.pool.query, oldMongo = mongo.getMongoDb;
  const oldSightingImage = sightingImages.findPublicSightingImage;
  const privateId = '507f1f77bcf86cd799439011';
  const publicPetId = '507f1f77bcf86cd799439012';
  const publicSightingId = '507f1f77bcf86cd799439013';
  const bytes = Buffer.from([255, 216, 255]);
  let mongoReads = 0;
  db.query = async (sql, values) => {
    if (sql.includes('FROM foto_mascota f')) {
      assert.match(sql, /r\.estado = 'ACTIVO' AND m\.estado = 'PERDIDA'/);
      assert.match(sql, /INTERVAL '30 days'/);
      return values[0] === publicPetId
        ? { rowCount: 1, rows: [{ fk_mascota: 4 }] } : { rowCount: 0, rows: [] };
    }
    assert.match(sql, /FROM foto_avistamiento fa/);
    assert.match(sql, /a\.estado IS DISTINCT FROM 'ELIMINADO'/);
    return values[0] === publicSightingId
      ? { rowCount: 1, rows: [{ id: 6 }] } : { rowCount: 0, rows: [] };
  };
  db.pool.query = db.query;
  mongo.getMongoDb = async () => ({
    collection(name) {
      assert.equal(name, 'ImagenMascota');
      return { async findOne(filter) {
        mongoReads++;
        assert.equal(filter._id.toHexString(), publicPetId);
        assert.equal(filter.mascotaIdPg, 4);
        assert.equal(filter.estado, 'ACTIVA');
        return { imagen: bytes, mimeType: 'image/jpeg' };
      } };
    },
  });
  sightingImages.findPublicSightingImage = async id => {
    mongoReads++;
    assert.equal(id, publicSightingId);
    return { imagen: bytes, mimeType: 'image/jpeg' };
  };
  t.after(() => {
    db.query = oldQuery;
    db.pool.query = oldPoolQuery;
    mongo.getMongoDb = oldMongo;
    sightingImages.findPublicSightingImage = oldSightingImage;
  });
  const app = express();
  app.use('/api/map', require('../src/modules/map/map.routes'));
  app.use('/api/sightings', require('../src/modules/sightings/sightings.routes'));
  app.use((error, req, res, next) => res.status(error.statusCode || 500).json({ ok: false }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = 'http://127.0.0.1:' + server.address().port;
  for (const prefix of ['/api/map/images/', '/api/sightings/images/']) {
    assert.equal((await fetch(base + prefix + privateId)).status, 404);
  }
  assert.equal(mongoReads, 0);
  // Las fotos públicas legítimas siguen disponibles sin autenticación.
  for (const path of ['/api/map/images/' + publicPetId, '/api/sightings/images/' + publicSightingId]) {
    const response = await fetch(base + path);
    assert.equal(response.status, 200);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), bytes);
  }
  assert.equal(mongoReads, 2);
});
