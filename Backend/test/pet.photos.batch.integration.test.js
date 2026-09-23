const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { once } = require('node:events');

const db = require('../src/config/postgres_db');
const imageRepository = require('../src/modules/pets/pets.images.repository');
const originalDeleteImage = imageRepository.eliminarImagenMascotaMongo;
let simulateMongoDeleteFailure = false;
imageRepository.eliminarImagenMascotaMongo = async (args) => {
  if (simulateMongoDeleteFailure) throw new Error('Fallo Mongo simulado');
  return originalDeleteImage(args);
};

const app = require('../src/app');
const { getMongoDb } = require('../src/config/mongo_db');
const { signAccessToken } = require('../src/utils/jwt');
const { hashText } = require('../src/utils/hash');

const integrationTest = process.env.ANIMAP_RUN_PET_BATCH_INTEGRATION === '1'
  ? test
  : test.skip;

function png(marker) {
  return Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, marker]);
}

function batchForm({ originalIds, retainedIds, principalExistingId, principalNewIndex, file }) {
  const form = new FormData();
  form.append('original_image_ids', JSON.stringify(originalIds));
  form.append('retained_image_ids', JSON.stringify(retainedIds));
  if (principalExistingId) form.append('principal_existing_id', principalExistingId);
  if (principalNewIndex !== undefined) {
    form.append('principal_new_index', String(principalNewIndex));
  }
  if (file) form.append('imagenes', new Blob([file], { type: 'image/png' }), 'nueva.png');
  return form;
}

integrationTest('lote de fotos valida antes de escribir y compensa un fallo Mongo', async () => {
  const suffix = randomUUID();
  const email = `pet-batch-${suffix}@example.invalid`;
  const passwordHash = await hashText(`Pet-${suffix.slice(0, 8)}-A1!`);
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  let userId;
  let petId;

  try {
    const species = await db.pool.query('SELECT id FROM especie ORDER BY id LIMIT 1');
    assert.equal(species.rowCount, 1);
    const user = await db.pool.query(
      `INSERT INTO usuario
         (nombre, email, telefono, password_hash, is_verified, acepta_tyc, estado_cuenta)
       VALUES ($1, $2, $3, $4, TRUE, TRUE, 'ACTIVO') RETURNING id`,
      ['Pet Batch E2E', email, '3000000000', passwordHash]
    );
    userId = user.rows[0].id;
    const pet = await db.pool.query(
      `INSERT INTO mascota
         (fk_usuario, fk_especie, nombre, color, sexo, estado)
       VALUES ($1, $2, $3, $4, 'NO_DEFINIDO', 'ACTIVA') RETURNING id`,
      [userId, species.rows[0].id, 'Pet Batch Temporal', 'Café']
    );
    petId = pet.rows[0].id;

    const seeded = await imageRepository.guardarImagenesMascota({
      mascotaIdPg: petId,
      usuarioIdPg: userId,
      files: Array.from({ length: 15 }, (_, index) => ({
        originalname: `seed-${index}.png`,
        mimetype: 'image/png',
        size: png(index).length,
        buffer: png(index),
      })),
      fotoPrincipalIndex: 0,
    });
    for (let index = 0; index < seeded.length; index += 1) {
      await db.pool.query(
        `INSERT INTO foto_mascota
           (fk_mascota, storage_ref, url_preview, es_principal)
         VALUES ($1, $2, $3, $4)`,
        [petId, seeded[index].storageRef, seeded[index].urlPreview, index === 0]
      );
    }

    const headers = {
      Authorization: `Bearer ${signAccessToken({ sub: String(userId) })}`,
    };
    const originalIds = seeded.map((item) => item.storageRef);

    const minimum = await fetch(`${baseUrl}/api/pets/${petId}/images/batch`, {
      method: 'PUT',
      headers,
      body: batchForm({
        originalIds,
        retainedIds: originalIds.slice(0, 14),
        principalExistingId: originalIds[0],
      }),
    });
    assert.equal(minimum.status, 409);
    assert.equal((await minimum.json()).code, 'MINIMUM_PET_PHOTOS_REQUIRED');

    const duplicate = await fetch(`${baseUrl}/api/pets/${petId}/images/batch`, {
      method: 'PUT',
      headers,
      body: batchForm({
        originalIds,
        retainedIds: originalIds,
        principalExistingId: originalIds[0],
        file: png(1),
      }),
    });
    assert.equal(duplicate.status, 409);

    simulateMongoDeleteFailure = true;
    const compensated = await fetch(`${baseUrl}/api/pets/${petId}/images/batch`, {
      method: 'PUT',
      headers,
      body: batchForm({
        originalIds,
        retainedIds: originalIds.slice(0, 14),
        principalExistingId: originalIds[0],
        file: png(99),
      }),
    });
    simulateMongoDeleteFailure = false;
    assert.equal(compensated.status, 500);

    const afterFailure = await db.pool.query(
      `SELECT storage_ref, es_principal FROM foto_mascota
       WHERE fk_mascota = $1 ORDER BY fecha, id`,
      [petId]
    );
    assert.equal(afterFailure.rowCount, 15);
    assert.deepEqual(new Set(afterFailure.rows.map((row) => row.storage_ref)), new Set(originalIds));
    assert.deepEqual(
      afterFailure.rows.filter((row) => row.es_principal).map((row) => row.storage_ref),
      [originalIds[0]]
    );
    const mongo = await getMongoDb();
    assert.equal(
      await mongo.collection('ImagenMascota').countDocuments({ mascotaIdPg: petId }),
      15
    );

    const success = await fetch(`${baseUrl}/api/pets/${petId}/images/batch`, {
      method: 'PUT',
      headers,
      body: batchForm({
        originalIds,
        retainedIds: originalIds.slice(0, 14),
        principalNewIndex: 0,
        file: png(100),
      }),
    });
    assert.equal(success.status, 200);
    const persisted = await db.pool.query(
      'SELECT storage_ref, es_principal FROM foto_mascota WHERE fk_mascota = $1',
      [petId]
    );
    assert.equal(persisted.rowCount, 15);
    assert.equal(persisted.rows.filter((row) => row.es_principal).length, 1);
    assert.notEqual(
      persisted.rows.find((row) => row.es_principal).storage_ref,
      originalIds[0]
    );
    assert.equal(
      await mongo.collection('ImagenMascota').countDocuments({ mascotaIdPg: petId }),
      15
    );
    const principalRef = persisted.rows.find((row) => row.es_principal).storage_ref;
    const atlasImage = await fetch(`${baseUrl}/api/pets/images/${principalRef}`, {
      headers,
    });
    assert.equal(atlasImage.status, 200);
    assert.equal(atlasImage.headers.get('content-type'), 'image/png');
    assert.deepEqual(
      Buffer.from(await atlasImage.arrayBuffer()),
      png(100)
    );
  } finally {
    simulateMongoDeleteFailure = false;
    if (petId) {
      const mongo = await getMongoDb();
      await mongo.collection('ImagenMascota').deleteMany({ mascotaIdPg: petId });
      await db.pool.query('DELETE FROM mascota WHERE id = $1 AND fk_usuario = $2', [petId, userId]);
    }
    if (userId) {
      await db.pool.query('DELETE FROM usuario WHERE id = $1 AND email = $2', [userId, email]);
      const residue = await db.pool.query(
        `SELECT
           (SELECT COUNT(*)::int FROM usuario WHERE id = $1) AS usuario,
           (SELECT COUNT(*)::int FROM mascota WHERE id = $2) AS mascota,
           (SELECT COUNT(*)::int FROM foto_mascota WHERE fk_mascota = $2) AS fotos`,
        [userId, petId || 0]
      );
      assert.deepEqual(residue.rows[0], { usuario: 0, mascota: 0, fotos: 0 });
    }
    await new Promise((resolve) => server.close(resolve));
  }
});
