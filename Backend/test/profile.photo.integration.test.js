const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { once } = require('node:events');

const app = require('../src/app');
const db = require('../src/config/postgres_db');
const { getMongoDb } = require('../src/config/mongo_db');
const { hashText } = require('../src/utils/hash');

const integrationTest =
  process.env.ANIMAP_RUN_PROFILE_INTEGRATION === '1' ? test : test.skip;

function photoForm(bytes, name, type) {
  const form = new FormData();
  form.append('foto', new Blob([bytes], { type }), name);
  return form;
}

integrationTest(
  'foto de perfil responde JSON, reemplaza Mongo y persiste en PostgreSQL',
  async () => {
    const suffix = randomUUID();
    const email = `profile-photo-${suffix}@example.invalid`;
    const password = `Photo-${suffix.slice(0, 8)}-A1!`;
    const passwordHash = await hashText(password);
    const server = app.listen(0, '127.0.0.1');
    await once(server, 'listening');
    const address = server.address();
    const baseUrl = `http://127.0.0.1:${address.port}`;
    let userId;

    try {
      const inserted = await db.pool.query(
        `INSERT INTO usuario
           (nombre, email, telefono, password_hash, is_verified, acepta_tyc, estado_cuenta)
         VALUES ($1, $2, $3, $4, TRUE, TRUE, 'ACTIVO')
         RETURNING id`,
        ['Profile Photo E2E', email, '3000000000', passwordHash],
      );
      userId = inserted.rows[0].id;
      await db.pool.query(
        'INSERT INTO perfil (fk_usuario) VALUES ($1)',
        [userId],
      );

      const login = await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password, deviceId: `profile-${suffix}` }),
      });
      assert.equal(login.status, 200);
      const accessToken = (await login.json()).data.accessToken;
      const headers = { Authorization: `Bearer ${accessToken}` };

      const invalid = await fetch(`${baseUrl}/api/profile/photo`, {
        method: 'POST',
        headers,
        body: photoForm(Uint8Array.from([1, 2, 3]), 'invalid.txt', 'text/plain'),
      });
      assert.equal(invalid.status, 400);
      assert.match(invalid.headers.get('content-type'), /application\/json/);
      assert.equal((await invalid.json()).ok, false);

      const oversizedBytes = new Uint8Array(5 * 1024 * 1024 + 1);
      oversizedBytes.set([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      ]);
      const oversized = await fetch(`${baseUrl}/api/profile/photo`, {
        method: 'POST',
        headers,
        body: photoForm(oversizedBytes, 'oversized.png', 'image/png'),
      });
      assert.equal(oversized.status, 400);
      assert.match(oversized.headers.get('content-type'), /application\/json/);
      assert.equal((await oversized.json()).ok, false);

      const pngA = Uint8Array.from([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1,
      ]);
      const first = await fetch(`${baseUrl}/api/profile/photo`, {
        method: 'POST',
        headers,
        body: photoForm(pngA, 'profile-a.png', 'image/png'),
      });
      assert.equal(first.status, 200);
      assert.match(first.headers.get('content-type'), /application\/json/);
      const firstBody = await first.json();
      const firstUrl = firstBody.data.foto_url;
      assert.match(firstUrl, /^\/api\/profile\/photo\/[a-f0-9]{24}$/);

      const photoResponse = await fetch(`${baseUrl}${firstUrl}`, { headers });
      assert.equal(photoResponse.status, 200);
      assert.equal(photoResponse.headers.get('content-type'), 'image/png');
      const signature = Buffer.from(await photoResponse.arrayBuffer()).subarray(0, 8);
      assert.equal(signature.toString('hex'), '89504e470d0a1a0a');

      const pngB = Uint8Array.from([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 2,
      ]);
      const second = await fetch(`${baseUrl}/api/profile/photo`, {
        method: 'POST',
        headers,
        body: photoForm(pngB, 'profile-b.png', 'image/png'),
      });
      assert.equal(second.status, 200);
      const secondBody = await second.json();
      assert.notEqual(secondBody.data.foto_url, firstUrl);

      const persisted = await db.pool.query(
        'SELECT foto_url, foto_storage_ref FROM perfil WHERE fk_usuario = $1',
        [userId],
      );
      assert.equal(persisted.rows[0].foto_url, secondBody.data.foto_url);
      const mongo = await getMongoDb();
      const images = mongo.collection('ImagenPerfil');
      assert.equal(await images.countDocuments({ usuarioIdPg: userId }), 1);
      const firstId = firstUrl.split('/').pop();
      assert.equal(await images.countDocuments({ _id: { $eq: new (require('mongodb').ObjectId)(firstId) } }), 0);
    } finally {
      if (userId) {
        const mongo = await getMongoDb();
        await mongo.collection('ImagenPerfil').deleteMany({ usuarioIdPg: userId });
        await db.pool.query(
          'DELETE FROM usuario WHERE id = $1 AND email = $2',
          [userId, email],
        );
        const residue = await db.pool.query(
          `SELECT
             (SELECT COUNT(*)::int FROM usuario WHERE id = $1) AS usuario,
             (SELECT COUNT(*)::int FROM perfil WHERE fk_usuario = $1) AS perfil,
             (SELECT COUNT(*)::int FROM device_session WHERE fk_usuario = $1) AS sesiones`,
          [userId],
        );
        assert.deepEqual(residue.rows[0], { usuario: 0, perfil: 0, sesiones: 0 });
      }
      await new Promise((resolve, reject) => {
        server.close((error) => (error ? reject(error) : resolve()));
      });
    }
  },
);
