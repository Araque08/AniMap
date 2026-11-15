const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { spawn, execFile } = require('node:child_process');
const exec = require('node:util').promisify(execFile);
const control = (exe, args) => new Promise((resolve, reject) => {
  const child = spawn(exe, args, { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk; });
  child.stderr.on('data', chunk => { output += chunk; });
  child.once('error', reject);
  child.once('exit', code => code === 0 ? resolve() : reject(Error(`Temporary PostgreSQL failed: ${output}`)));
});

// Own ephemeral cluster only; never use DB_* variables or a shared server.
test('HU034 durable matches and bounded leased analysis in isolated PostgreSQL', {
  skip: process.env.ANIMAP_RUN_MATCHES_PG !== '1', timeout: 90000,
}, async t => {
  const bin = process.env.ANIMAP_TEST_PG_BIN;
  assert.ok(bin);
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'animap80-pg-'));
  const data = path.join(root, 'data');
  const socket = net.createServer();
  await new Promise(resolve => socket.listen(0, '127.0.0.1', resolve));
  const port = socket.address().port;
  await new Promise(resolve => socket.close(resolve));
  let pool, started = false, modelWorker = null;
  try {
    await exec(path.join(bin, 'initdb.exe'), ['-D', data, '-U', 'animap_test', '-A', 'trust', '--no-locale', '-E', 'UTF8']);
    await control(path.join(bin, 'pg_ctl.exe'), ['-D', data, '-l', path.join(root, 'postgres.log'), '-o', `-h 127.0.0.1 -p ${port} -F`, '-w', 'start']);
    started = true;
    // This opt-in test owns the cluster/port. Even default adapters must stay
    // inside it; never inherit credentials or destinations from a developer.
    Object.assign(process.env, { DB_HOST: '127.0.0.1', DB_PORT: String(port),
      DB_USER: 'animap_test', DB_PASSWORD: '', DB_NAME: 'postgres', DB_SSL: 'false',
      MONGO_URI: 'mongodb://127.0.0.1:1/isolated', MONGO_DB_NAME: 'isolated',
      PHOTO_MATCH_ENABLED: 'true', FCM_PUSH_ENABLED: 'false' });
    pool = new (require('pg').Pool)({ host: '127.0.0.1', port, user: 'animap_test', database: 'postgres', max: 4,
      options: '-c timezone=America/Bogota' });
    const schema = await fs.readFile(path.join(__dirname, '../../animap_bd.sql'), 'utf8');
    await pool.query(schema.slice(0, schema.indexOf('INSERT INTO rol')));
    for (const name of ['20261031_fcm_session_registration.sql', '20261101_sighting_push_notifications.sql',
      '20261102_independent_push_registration.sql']) {
      await pool.query(await fs.readFile(path.join(__dirname, '../database/migrations', name), 'utf8'));
    }
    await pool.query(`INSERT INTO usuario(id,nombre,email,telefono,password_hash,is_verified) VALUES
      (1,'Owner','owner@example.test','111','hash',TRUE),(2,'Reporter','reporter@example.test','222','hash',TRUE),
      (3,'Other','other@example.test','333','hash',TRUE);
      INSERT INTO perfil(fk_usuario) VALUES(1),(2),(3);
      INSERT INTO especie(id,nombre) VALUES(1,'Perro');
      INSERT INTO mascota(id,fk_usuario,fk_especie,nombre,color,estado) VALUES(1,1,1,'Luna','cafe','PERDIDA');
      INSERT INTO reporte(id,fk_usuario,fk_mascota) VALUES(1,1,1);
      INSERT INTO foto_mascota(id,fk_mascota,storage_ref) VALUES(1,1,'507f1f77bcf86cd799439011');
      INSERT INTO avistamiento(id,fk_usuario,estado) VALUES(1,2,'ACTIVO'),(2,2,'ACTIVO'),(3,2,'ACTIVO');
      INSERT INTO foto_avistamiento(id,fk_avistamiento,storage_ref) VALUES(1,1,'507f1f77bcf86cd799439012');
      INSERT INTO ubicacion(fk_avistamiento,metodo,lat,lng,direccion) VALUES(1,'MAPA',4.6,-74.1,'QA');
      INSERT INTO ubicacion(fk_reporte,metodo,lat,lng) VALUES(1,'GPS',4.6,-74.1);
      INSERT INTO coincidencia_reconocimiento(fk_foto_avistamiento,fk_foto_mascota,similitud,umbral_usado) VALUES(1,1,81,75);`);
    await pool.query("UPDATE avistamiento SET fecha_hora='2020-01-02 03:04:05.123' WHERE id=1");
    const migrationPath = path.join(__dirname, '../database/migrations/20261108_photo_match_notifications.sql');
    assert.ok(await fs.access(migrationPath).then(() => true, () => false), 'HU034 migration must exist');
    const migration = await fs.readFile(migrationPath, 'utf8');
    await pool.query(migration);
    await pool.query(migration);
    let mongoDocument = { imagen: Buffer.from('image'), mimeType: 'image/jpeg' };
    let mongoFilter;
    const repo = require('../src/modules/recognition/recognition.matches.repository').createMatchRepository({ pool,
      mongo: async () => ({ collection: name => {
        assert.equal(name, 'ImagenAvistamiento');
        return { findOne: async filter => { mongoFilter = filter; return mongoDocument; } };
      } }),
    });
    const request = { sightingId: 1, userId: 2, requestId: '11111111-1111-4111-8111-111111111111', fingerprint: 'a'.repeat(64), shareContact: false };
    let event, matchId, job;
    await t.test('owner recovery cannot reclaim community or administrative deliveries', async () => {
      const { createNotificationsRepository } = require('../src/modules/notifications/notifications.repository');
      const deliveries = createNotificationsRepository(pool);
      await pool.query(`INSERT INTO notificacion(id,fk_usuario,fk_reporte,titulo,mensaje,tipo,estado_envio)
        VALUES (90001,1,1,'QA','QA','AVISTAMIENTO_VINCULADO','PENDIENTE'),
          (90002,1,1,'QA','QA','COINCIDENCIA_FOTOGRAFICA','PENDIENTE'),
          (90003,1,1,'QA','QA','PERDIDA_CERCANA','PENDIENTE'),
          (90004,1,1,'QA','QA','ADMINISTRATIVA','PENDIENTE');
        INSERT INTO notificacion_entrega(fk_notificacion,registro_huella,estado,iniciado_en)
        SELECT id,lpad(to_hex(id),64,'0'),'EN_PROCESO',
          (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '20 minutes'
        FROM notificacion WHERE id BETWEEN 90001 AND 90004;`);
      try {
        await deliveries.recoverAbandoned();
        const states = (await pool.query(`SELECT fk_notificacion,estado FROM notificacion_entrega
          WHERE fk_notificacion BETWEEN 90001 AND 90004 ORDER BY fk_notificacion`)).rows;
        assert.deepEqual(states.map(row => row.estado),
          ['INDETERMINADA','INDETERMINADA','EN_PROCESO','EN_PROCESO']);
        await deliveries.recoverCommunityAbandoned();
        assert.deepEqual((await pool.query(`SELECT estado FROM notificacion_entrega
          WHERE fk_notificacion BETWEEN 90001 AND 90004 ORDER BY fk_notificacion`)).rows.map(row => row.estado),
          ['INDETERMINADA','INDETERMINADA','INDETERMINADA','EN_PROCESO']);
      } finally {
        await pool.query('DELETE FROM notificacion WHERE id BETWEEN 90001 AND 90004');
      }
    });
    await t.test('request uniqueness and transaction rollback prevent duplicate publications', async () => {
      await repo.transaction(client => repo.enqueue(client, request));
      const existing = await repo.findRequest(pool, 2, request.requestId);
      assert.equal(existing.sightingId, 1);
      assert.equal(existing.fingerprint, 'a'.repeat(64));
      await assert.rejects(repo.transaction(client => repo.enqueue(client, { ...request, sightingId: 2 })), { code: '23505' });
      await assert.rejects(repo.transaction(async client => {
        await repo.enqueue(client, { ...request, sightingId: 2, requestId: '22222222-2222-4222-8222-222222222222' });
        throw Error('rollback');
      }), /rollback/);
      assert.equal(await repo.findRequest(pool, 2, '22222222-2222-4222-8222-222222222222'), null);
    });
    await t.test('claim is exclusive, source photo is bound to actual author and sighting', async () => {
      const claims = await Promise.all([repo.claim(), repo.claim()]);
      assert.equal(claims.filter(Boolean).length, 1);
      job = claims.find(Boolean);
      assert.equal(job.attempts, 1);
      assert.deepEqual(await repo.photo(job), Buffer.from('image'));
      assert.equal(mongoFilter.avistamientoIdPg, 1);
      assert.equal(mongoFilter.usuarioIdPg, 2);
      assert.equal(mongoFilter._id.toHexString(), '507f1f77bcf86cd799439012');
      mongoDocument = { imagen: Buffer.alloc(5 * 1024 * 1024 + 1), mimeType: 'image/jpeg' };
      assert.equal(await repo.photo(job), null);
      mongoDocument = { imagen: Buffer.from('image'), mimeType: 'image/jpeg' };
    });
    await t.test('candidate revalidates owner/report/photo and persisted match is idempotent', async () => {
      const analysisStartedAt = Date.now();
      await repo.transaction(async client => {
        assert.equal(await repo.isCurrent(client, job), true);
        event = await repo.candidate(client, 1, 1, '507f1f77bcf86cd799439011');
        assert.equal(event.ownerId, 1);
        assert.equal(event.authorId, 2);
        assert.equal(event.sightingPhotoId, 1);
        assert.equal(event.photoMetadataId, 1);
        assert.equal(event.notificationsEnabled, true);
        assert.equal(await repo.candidate(client, 1, 1, '507f1f77bcf86cd799439099'), null);
        matchId = await repo.saveMatch(client, event, { similarity: 0.91, threshold: 0.75, model: 'resnet50-v1', notificationId: null });
        assert.equal(await repo.saveMatch(client, event, { similarity: 0.91, threshold: 0.75, model: 'resnet50-v1', notificationId: null }), matchId);
        assert.equal(await repo.complete(client, job), true);
      });
      const persisted = await pool.query('SELECT similitud,umbral_usado FROM coincidencia_reconocimiento WHERE id=$1', [matchId]);
      assert.deepEqual(persisted.rows[0], { similitud: '91.00', umbral_usado: '75.00' });
      const detail = await repo.detail(1, matchId);
      assert.equal(detail.observedAt, '2020-01-02T03:04:05.123Z');
      assert.equal(typeof detail.createdAt, 'string');
      assert.match(detail.createdAt, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/);
      assert.ok(Date.parse(detail.createdAt) >= analysisStartedAt - 1);
      assert.ok(Date.parse(detail.createdAt) <= Date.now());
      assert.ok(Date.parse(detail.createdAt) > Date.parse(detail.observedAt));
      await pool.query("UPDATE reporte SET estado='FINALIZADO' WHERE id=1");
      assert.equal(await repo.candidate(pool, 1, 1, '507f1f77bcf86cd799439011'), null);
      await pool.query("UPDATE reporte SET estado='ACTIVO' WHERE id=1");
    });
    await t.test('candidate transaction prevents report close and preference changes before persistence', async () => {
      await pool.query("INSERT INTO preferencia_notificacion(fk_usuario,tipo_evento) VALUES(1,'AVISTAMIENTO')");
      const writer = await pool.connect();
      try {
        await writer.query("SET lock_timeout='100ms'");
        await repo.transaction(async client => {
          assert.ok(await repo.candidate(client, 1, 1, '507f1f77bcf86cd799439011'));
          await assert.rejects(writer.query("UPDATE reporte SET estado='FINALIZADO' WHERE id=1"), { code: '55P03' });
          await assert.rejects(writer.query('UPDATE perfil SET notificaciones_activas=FALSE WHERE fk_usuario=1'), { code: '55P03' });
          await assert.rejects(writer.query("UPDATE preferencia_notificacion SET tipo_evento='OTRO' WHERE fk_usuario=1"), { code: '55P03' });
        });
      } finally { writer.release(); }
    });
    await t.test('history and photo enforce recipient ownership and consent without email', async () => {
      assert.deepEqual(await repo.list(3), []);
      assert.equal(await repo.detail(3, matchId), null);
      assert.equal(await repo.image(3, matchId), null);
      const detail = await repo.detail(1, matchId);
      assert.equal(detail.similarity, 0.91);
      assert.equal(detail.threshold, 0.75);
      assert.equal(detail.reporter.label, 'Reportante');
      assert.equal(detail.reporter.phone, undefined);
      assert.equal(detail.pet.name, 'Luna');
      assert.deepEqual(detail.location, { lat: 4.6, lng: -74.1, method: 'MAPA', address: 'QA' });
      assert.equal(JSON.stringify(detail).includes('example.test'), false);
      assert.equal(detail.photoUrl, `/api/recognition/matches/${matchId}/image`);
      assert.deepEqual(await repo.image(1, matchId), { buffer: Buffer.from('image'), mimeType: 'image/jpeg' });
      await pool.query('UPDATE reconocimiento_publicacion SET compartir_contacto=TRUE WHERE fk_avistamiento=1');
      assert.equal((await repo.detail(1, matchId)).reporter.phone, '222');
      assert.equal((await repo.detail(1, matchId)).reporter.label, 'Reporter');
      assert.equal((await repo.list(1)).length, 1);
      assert.deepEqual(await repo.list(1, matchId), []);
    });
    await t.test('reference photo deletion preserves existing and owner history', async () => {
      await pool.query('DELETE FROM foto_mascota WHERE id=1');
      assert.equal((await pool.query('SELECT count(*) FROM coincidencia_reconocimiento')).rows[0].count, '2');
      assert.equal((await repo.detail(1, matchId)).id, matchId);
    });
    await t.test('expired claims are fenced and retried at most three times with safe error codes', async () => {
      await repo.transaction(client => repo.enqueue(client, { ...request, sightingId: 2, requestId: '22222222-2222-4222-8222-222222222222' }));
      const first = await repo.claim();
      await pool.query("UPDATE reconocimiento_publicacion SET reclamado_en=NOW()-INTERVAL '20 minutes' WHERE fk_avistamiento=2");
      const second = await repo.claim();
      assert.equal(second.attempts, 2);
      assert.notEqual(first.claimId, second.claimId);
      assert.equal(await repo.transaction(client => repo.complete(client, first)), false);
      assert.equal(await repo.transaction(client => repo.fail(client, second, 'secret email or SQL')), false);
      assert.equal((await pool.query('SELECT ultimo_error FROM reconocimiento_publicacion WHERE fk_avistamiento=2')).rows[0].ultimo_error, 'ANALYSIS_FAILED');
      await pool.query('UPDATE reconocimiento_publicacion SET proximo_intento_en=NOW() WHERE fk_avistamiento=2');
      const third = await repo.claim();
      assert.equal(third.attempts, 3);
      assert.equal(await repo.transaction(client => repo.fail(client, third, 'ANALYSIS_FAILED')), true);
      assert.equal(await repo.claim(), null);
      const state = (await pool.query('SELECT estado,ultimo_error FROM reconocimiento_publicacion WHERE fk_avistamiento=2')).rows[0];
      assert.deepEqual(state, { estado: 'FALLIDA', ultimo_error: 'ANALYSIS_FAILED' });
    });
    await t.test('abandoned third claim is fenced and returned only for final fallback without another analysis', async () => {
      await repo.transaction(client => repo.enqueue(client, { ...request, sightingId: 3,
        requestId: '33333333-3333-4333-8333-333333333333' }));
      const first = await repo.claim();
      assert.equal(first.exhausted, false);
      await pool.query("UPDATE reconocimiento_publicacion SET reclamado_en=NOW()-INTERVAL '20 minutes' WHERE fk_avistamiento=3");
      const second = await repo.claim();
      assert.equal(second.attempts, 2);
      await pool.query("UPDATE reconocimiento_publicacion SET reclamado_en=NOW()-INTERVAL '20 minutes' WHERE fk_avistamiento=3");
      const third = await repo.claim();
      assert.equal(third.attempts, 3);
      assert.equal(third.exhausted, false);
      await pool.query("UPDATE reconocimiento_publicacion SET reclamado_en=NOW()-INTERVAL '20 minutes' WHERE fk_avistamiento=3");
      const finalizer = await repo.claim();
      assert.equal(finalizer.attempts, 3);
      assert.equal(finalizer.exhausted, true);
      assert.notEqual(finalizer.claimId, third.claimId);
      assert.equal(await repo.claim(), null);
      assert.equal(await repo.transaction(client => repo.complete(client, third)), false);
      assert.equal(await repo.transaction(client => repo.fail(client, finalizer, 'MATCH_ANALYSIS_EXHAUSTED', { permanent: true })), true);
    });
    await t.test('real publication and analysis coalesce linked alert and deliver one private photo event', async () => {
      await pool.query(`SELECT setval(pg_get_serial_sequence('avistamiento','id'),3);
        SELECT setval(pg_get_serial_sequence('foto_avistamiento','id'),1);
        INSERT INTO foto_mascota(id,fk_mascota,storage_ref) VALUES(2,1,'507f1f77bcf86cd799439011');
        INSERT INTO device_push_registration(fk_usuario,device_id,fcm_registration_id)
          VALUES(1,'isolated-qa','isolated-fcm-registration');`);
      const deliveries = [];
      const { createNotificationsRepository } = require('../src/modules/notifications/notifications.repository');
      const { createNotificationsService } = require('../src/modules/notifications/notifications.service');
      const notifications = createNotificationsService({ repo: createNotificationsRepository(pool),
        enabled: true, testMode: false, processingMode: 'scheduled',
        sender: { send: async payload => { deliveries.push(payload); return 'isolated-message-id'; } },
      });
      const { createMatchService } = require('../src/modules/recognition/recognition.matches.service');
      let analyses = 0;
      const realModel = process.env.ANIMAP_RUN_MATCHES_RESNET === '1';
      let recognizer;
      let photoBytes = Buffer.from('image');
      if (realModel) {
        const { RecognitionWorker } = require('../src/modules/recognition/recognition.worker');
        const { createRecognitionService } = require('../src/modules/recognition/recognition.service');
        const { createRecognitionRepository } = require('../src/modules/recognition/recognition.repository');
        photoBytes = await fs.readFile(process.env.ANIMAP_TEST_MATCH_IMAGE
          || path.join(__dirname, '../../Reconocimiento/imagenes_prueba/mascota1.jpeg'));
        mongoDocument = { imagen: photoBytes, mimeType: 'image/jpeg' };
        modelWorker = new RecognitionWorker();
        recognizer = createRecognitionService({ worker: modelWorker,
          repo: createRecognitionRepository({ pool, mongo: async () => ({ collection: name => {
            assert.equal(name, 'ImagenMascota');
            return { findOne: async filter => {
              assert.equal(filter.mascotaIdPg, 1);
              assert.equal(filter.usuarioIdPg, 1);
              assert.equal(filter.estado, 'ACTIVA');
              return { imagen: photoBytes };
            } };
          } }) }),
        });
      }
      assert.equal(require('../src/config/env').PHOTO_MATCH_ENABLED, true);
      assert.equal(require('../src/config/env').FCM_PUSH_ENABLED, false);
      const matches = createMatchService({ repo, notifications, enabled: true, processingMode: 'scheduled',
        recognizer: { search: async (...args) => {
          analyses++;
          if (realModel) return recognizer.search(...args);
          return { model: 'resnet50-imagenet1k-v2', threshold: 0.8,
            matches: [{ reportId: 1, similarity: 0.94, photo: { id: '507f1f77bcf86cd799439011' } }] };
        } },
      });
      // Importing the legacy default images adapter constructs a MongoClient.
      // Replace only its external configuration boundary; all SQL stays real.
      const mongoModule = require.resolve('../src/config/mongo_db');
      const previousMongo = require.cache[mongoModule];
      require.cache[mongoModule] = { id: mongoModule, filename: mongoModule, loaded: true,
        exports: { getMongoDb: async () => { throw Error('External MongoDB is forbidden in isolated SQL tests'); } } };
      let createSightingsService;
      try { ({ createSightingsService } = require('../src/modules/sightings/sightings.service')); }
      finally { if (previousMongo) require.cache[mongoModule] = previousMongo; else delete require.cache[mongoModule]; }
      let saves = 0;
      const sightings = createSightingsService(pool, {
        saveSightingImage: async () => {
          saves++;
          return { storageRef: '507f1f77bcf86cd799439013', urlPreview: '/qa-image' };
        }, deleteSightingImage: async () => { throw Error('Committed image must not be deleted'); },
      }, { validateAllowedArea: () => {} }, notifications, matches);
      const data = { descripcion: 'QA publication', reportId: 1, metodo: 'MAPA', lat: 4.6, lng: -74.1,
        precisionM: null, direccion: 'QA', placeId: null, ubicacionConfirmada: true, compartirContacto: false,
        solicitudId: '44444444-4444-4444-8444-444444444444' };
      const file = { buffer: photoBytes, mimetype: 'image/jpeg' };
      const publications = await Promise.all([sightings.createSighting(2, data, file), sightings.createSighting(2, data, file)]);
      assert.equal(publications[0].id, publications[1].id);
      assert.equal(saves, 1);
      const sightingId = publications[0].id;
      assert.equal((await pool.query('SELECT count(*) FROM notificacion WHERE fk_avistamiento=$1', [sightingId])).rows[0].count, '0');
      assert.deepEqual(await matches.drain(), { enabled: true, completed: true });
      assert.equal(analyses, 1);
      const intents = (await pool.query(`SELECT id,tipo AS type,fk_usuario AS "ownerId",fk_reporte AS "reportId",
        fk_avistamiento AS "sightingId" FROM notificacion WHERE fk_avistamiento=$1`, [sightingId])).rows;
      assert.equal(intents.length, 1);
      assert.equal(intents[0].type, 'COINCIDENCIA_FOTOGRAFICA');
      const current = await repo.loadNotification(pool, intents[0]);
      assert.equal(current.ownerId, 1);
      if (realModel) assert.ok(current.similarity >= 0.9999 && current.similarity <= 1);
      else assert.equal(current.similarity, 0.94);
      assert.equal(current.reportState, 'ACTIVO');
      assert.equal((await matches.detail(1, current.matchId)).reporter.label, 'Reportante');
      await notifications.drain();
      await notifications.drain();
      assert.equal(deliveries.length, 1);
      assert.deepEqual(deliveries[0].data, { type: 'COINCIDENCIA_FOTOGRAFICA', matchId: String(current.matchId),
        notificationId: String(intents[0].id), sightingId: String(sightingId), reportId: '1', ownerId: '1' });
      assert.equal(JSON.stringify(deliveries[0]).includes('/qa-image'), false);
      assert.equal((await matches.detail(1, current.matchId)).notificationState, 'ACEPTADA_FCM');
      assert.deepEqual((await matches.image(1, current.matchId)).buffer, photoBytes);
      assert.equal(await repo.detail(3, current.matchId), null);
      assert.deepEqual((await pool.query(`SELECT r.estado AS report_state,m.estado AS pet_state
        FROM reporte r JOIN mascota m ON m.id=r.fk_mascota WHERE r.id=1`)).rows[0],
      { report_state: 'ACTIVO', pet_state: 'PERDIDA' });
      await pool.query("UPDATE reporte SET estado='FINALIZADO' WHERE id=1");
      assert.equal((await repo.loadNotification(pool, intents[0])).reportState, 'FINALIZADO');
      await pool.query('UPDATE reporte SET fk_usuario=3 WHERE id=1');
      assert.equal(await repo.loadNotification(pool, intents[0]), null);
      notifications.stop(); matches.stop();
    });
  } catch (error) {
    const log = await fs.readFile(path.join(root, 'postgres.log'), 'utf8').catch(() => '');
    error.message += log;
    throw error;
  } finally {
    modelWorker?.close();
    await pool?.end();
    if (started) await control(path.join(bin, 'pg_ctl.exe'), ['-D', data, '-m', 'fast', '-w', 'stop']);
    if (path.dirname(root) === os.tmpdir() && path.basename(root).startsWith('animap80-pg-')) await fs.rm(root, { recursive: true, force: true });
  }
});
