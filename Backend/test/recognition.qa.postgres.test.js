const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { spawn } = require('node:child_process');
const { MongoClient, ObjectId } = require('mongodb');
const scope = { mode: true, testMode: true, ownerId: 101, reportId: 201, reporterId: 102 };
const control = (exe, args) => new Promise((resolve, reject) => {
  const child = spawn(exe, args, { windowsHide: true, stdio: ['ignore','pipe','pipe'] });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk; });
  child.stderr.on('data', chunk => { output += chunk; });
  child.once('error', reject);
  child.once('exit', code => code === 0 ? resolve() : reject(Error(output)));
});
async function freePort() {
  const socket = net.createServer();
  await new Promise(resolve => socket.listen(0, '127.0.0.1', resolve));
  const port = socket.address().port;
  await new Promise(resolve => socket.close(resolve));
  return port;
}

test('QA isolation with owned temporary PostgreSQL and MongoDB', {
  skip: process.env.ANIMAP_RUN_RECOGNITION_QA_DB !== '1', timeout: 120000,
}, async t => {
  const pgBin = process.env.ANIMAP_TEST_PG_BIN;
  const mongod = process.env.ANIMAP_TEST_MONGOD;
  assert.ok(pgBin && mongod, 'Explicit local executables required');
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'animap80-scope-'));
  const pgData = path.join(root, 'postgres'), mongoData = path.join(root, 'mongo');
  const pgPort = await freePort(), mongoPort = await freePort();
  let started = false, mongoProcess, client, pool;
  try {
    await control(path.join(pgBin, 'initdb.exe'), ['-D', pgData, '-U', 'animap_test', '-A', 'trust', '--no-locale', '-E', 'UTF8']);
    await control(path.join(pgBin, 'pg_ctl.exe'), ['-D', pgData, '-l', path.join(root, 'postgres.log'), '-o', `-h 127.0.0.1 -p ${pgPort} -F`, '-w', 'start']);
    started = true;
    await fs.mkdir(mongoData);
    mongoProcess = spawn(mongod, ['--dbpath', mongoData, '--port', String(mongoPort), '--bind_ip', '127.0.0.1', '--logpath', path.join(root, 'mongo.log'), '--quiet'],
      { windowsHide: true, stdio: 'ignore' });
    Object.assign(process.env, { DB_HOST: '127.0.0.1', DB_PORT: String(pgPort), DB_USER: 'animap_test',
      DB_PASSWORD: '', DB_NAME: 'postgres', DB_SSL: 'false', MONGO_URI: `mongodb://127.0.0.1:${mongoPort}`,
      MONGO_DB_NAME: 'synthetic_scope', FCM_PUSH_ENABLED: 'false', PHOTO_MATCH_ENABLED: 'false' });
    pool = new (require('pg').Pool)({ host: '127.0.0.1', port: pgPort, user: 'animap_test', database: 'postgres', max: 4 });
    client = new MongoClient(process.env.MONGO_URI, { serverSelectionTimeoutMS: 10000, monitorCommands: true });
    await client.connect();
    const mongo = client.db('synthetic_scope'), reads = [];
    client.on('commandStarted', event => {
      if (event.commandName === 'find') reads.push({ collection: event.command.find, filter: event.command.filter });
    });
    const schema = await fs.readFile(path.join(__dirname, '../../animap_bd.sql'), 'utf8');
    await pool.query(schema.slice(0, schema.indexOf('INSERT INTO rol')));
    for (const migration of ['20261031_fcm_session_registration.sql', '20261101_sighting_push_notifications.sql',
      '20261102_independent_push_registration.sql', '20261108_photo_match_notifications.sql']) {
      await pool.query(await fs.readFile(path.join(__dirname, '../database/migrations', migration), 'utf8'));
    }
    await pool.query(`INSERT INTO usuario(id,nombre,email,telefono,password_hash,is_verified) VALUES
      (101,'Synthetic QA Owner','owner@example.invalid','111','hash',TRUE),
      (102,'Synthetic QA Reporter','reporter@example.invalid','222','hash',TRUE),
      (103,'Other Owner','other@example.invalid','333','hash',TRUE),
      (104,'Other Reporter','other-reporter@example.invalid','444','hash',TRUE);
      INSERT INTO perfil(fk_usuario) VALUES(101),(102),(103),(104);
      INSERT INTO especie(id,nombre) VALUES(1,'Perro');
      INSERT INTO mascota(id,fk_usuario,fk_especie,nombre,color,estado) VALUES
        (301,101,1,'QA Nube','cafe','PERDIDA'),(302,103,1,'Other','gris','PERDIDA'),(303,101,1,'Another QA','blanco','PERDIDA');
      INSERT INTO reporte(id,fk_usuario,fk_mascota) VALUES(201,101,301),(202,103,302),(203,101,303);
      INSERT INTO foto_mascota(id,fk_mascota,storage_ref) VALUES
        (401,301,'507f1f77bcf86cd799439011'),(402,302,'507f1f77bcf86cd799439012'),(403,303,'507f1f77bcf86cd799439013');
      INSERT INTO avistamiento(id,fk_usuario,fk_reporte_perdida,estado) VALUES
        (501,104,NULL,'ACTIVO'),(502,102,NULL,'ACTIVO'),(503,102,202,'ACTIVO'),(504,104,NULL,'ACTIVO');
      INSERT INTO foto_avistamiento(id,fk_avistamiento,storage_ref) VALUES(601,502,'507f1f77bcf86cd799439021');
      INSERT INTO ubicacion(fk_avistamiento,metodo,lat,lng) VALUES(502,'MAPA',4.6455,-74.1105);
      INSERT INTO ubicacion(fk_reporte,metodo,lat,lng) VALUES(201,'MAPA',4.6455,-74.1105);
      INSERT INTO reconocimiento_publicacion(fk_avistamiento,fk_usuario,solicitud_id,huella) VALUES
        (501,104,'11111111-1111-4111-8111-111111111111',repeat('a',64)),
        (502,102,'22222222-2222-4222-8222-222222222222',repeat('b',64)),
        (503,102,'33333333-3333-4333-8333-333333333333',repeat('c',64)),
        (504,104,'44444444-4444-4444-8444-444444444444',repeat('d',64));
      UPDATE reconocimiento_publicacion SET estado='EN_PROCESO',intentos=3,reclamado_en=NOW()-INTERVAL '1 hour'
        WHERE fk_avistamiento=504;`);
    await mongo.collection('ImagenMascota').insertMany([11,12,13].map((suffix,index) => ({
      _id: new ObjectId(`507f1f77bcf86cd7994390${suffix}`), mascotaIdPg: 301+index,
      usuarioIdPg: index===1?103:101, estado:'ACTIVA', imagen:Buffer.from('synthetic-'+suffix), mimeType:'image/png' })));
    await mongo.collection('ImagenAvistamiento').insertOne({ _id:new ObjectId('507f1f77bcf86cd799439021'),
      avistamientoIdPg:502, usuarioIdPg:102,imagen:Buffer.from('synthetic-query'),mimeType:'image/png' });
    const { createRecognitionRepository } = require('../src/modules/recognition/recognition.repository');
    const { createRecognitionService } = require('../src/modules/recognition/recognition.service');
    const { createMatchRepository } = require('../src/modules/recognition/recognition.matches.repository');
    const repo = createRecognitionRepository({ pool, mongo:async()=>mongo, qaScope:scope });
    const jobs = createMatchRepository({ pool, mongo:async()=>mongo, qaScope:scope });
    const worker = { request:async(action)=> action==='query'?{queryId:'synthetic-query'}:action==='compare'?{similarity:0.97}:{},close(){} };
    const makeRecognizer = (workerOverride=worker) => createRecognitionService({ repo, worker:workerOverride });
    const foreignBefore = (await pool.query(`SELECT * FROM reconocimiento_publicacion WHERE fk_avistamiento IN (501,503,504) ORDER BY fk_avistamiento`)).rows;

    await t.test('SQL selects only authorized owner and report before Mongo reads', async()=>{
      assert.deepEqual((await repo.activePhotos()).map(p=>p.reportId),[201]);
      reads.length=0;
      const result = await makeRecognizer().search(Buffer.from('synthetic-query'));
      assert.deepEqual(result.matches.map(m=>m.reportId),[201]);
      assert.equal(result.searchedImages,1);
      assert.equal(reads.length,2);
      assert.ok(reads.every(r=>r.collection==='ImagenMascota' && r.filter.mascotaIdPg===301 && r.filter.usuarioIdPg===101));
    });
    await t.test('second candidate read rejects QA report closed during comparison', async()=>{
      const closingWorker = { ...worker, request:async(action,payload)=>{
        if(action==='compare') await pool.query("UPDATE reporte SET estado='FINALIZADO' WHERE id=201");
        return worker.request(action,payload);
      }};
      try { assert.deepEqual((await makeRecognizer(closingWorker).search(Buffer.from('synthetic-query'))).matches,[]); }
      finally { await pool.query("UPDATE reporte SET estado='ACTIVO' WHERE id=201"); }
    });
    await t.test('invalid owner relation or inactive pet prevents candidate and job selection', async()=>{
      for(const sql of ["UPDATE mascota SET estado='INACTIVA' WHERE id=301",'UPDATE mascota SET fk_usuario=103 WHERE id=301']) {
        await pool.query(sql);
        try { assert.deepEqual(await repo.activePhotos(),[]); assert.equal(await jobs.claim(),null); }
        finally { await pool.query("UPDATE mascota SET estado='PERDIDA',fk_usuario=101 WHERE id=301"); }
      }
    });
    await t.test('concurrent recovery never claims another author or a different linked report', async()=>{
      const claims = await Promise.all([jobs.claim(),jobs.claim()]);
      assert.deepEqual(claims.filter(Boolean).map(j=>j.sightingId),[502]);
      assert.deepEqual((await pool.query(`SELECT * FROM reconocimiento_publicacion WHERE fk_avistamiento IN (501,503,504) ORDER BY fk_avistamiento`)).rows,foreignBefore);
      await pool.query("UPDATE reconocimiento_publicacion SET estado='PENDIENTE',intentos=0,reclamo_id=NULL,reclamado_en=NULL,proximo_intento_en=NOW() WHERE fk_avistamiento=502");
    });
    await t.test('persistent match, deduplication, private history and disabled FCM', async()=>{
      const { createNotificationsRepository } = require('../src/modules/notifications/notifications.repository');
      const { createNotificationsService } = require('../src/modules/notifications/notifications.service');
      let sends=0;
      const notifications = createNotificationsService({ repo:createNotificationsRepository(pool), enabled:false,
        testMode:true,testOwnerId:101,testReportId:201,sender:{send:async()=>{sends++;throw Error('FCM forbidden');}} });
      const { createMatchService } = require('../src/modules/recognition/recognition.matches.service');
      const service = createMatchService({repo:jobs,recognizer:makeRecognizer(),notifications,enabled:true});
      await service.drain(); await notifications.drain();
      const matches=(await pool.query('SELECT * FROM coincidencia_reconocimiento')).rows;
      assert.equal(matches.length,1);assert.equal(matches[0].fk_usuario,101);assert.equal(matches[0].fk_reporte,201);
      const id=matches[0].id;
      assert.equal((await jobs.detail(101,id)).reporter.label,'Reportante');
      assert.equal(await jobs.detail(103,id),null);assert.equal(await jobs.image(103,id),null);
      assert.deepEqual((await jobs.image(101,id)).buffer,Buffer.from('synthetic-query'));
      assert.equal((await pool.query('SELECT estado FROM reconocimiento_publicacion WHERE fk_avistamiento=502')).rows[0].estado,'COMPLETADA');
      await pool.query("UPDATE reconocimiento_publicacion SET estado='REINTENTO',proximo_intento_en=NOW() WHERE fk_avistamiento=502");
      // A fresh processor represents restart; unrelated pending/expired jobs still exist.
      const restarted=createMatchService({repo:jobs,recognizer:makeRecognizer(),notifications,enabled:true});
      await restarted.drain();await notifications.drain();
      assert.equal((await pool.query('SELECT count(*) FROM coincidencia_reconocimiento')).rows[0].count,'1');
      assert.equal((await pool.query('SELECT count(*) FROM notificacion')).rows[0].count,'1');
      assert.equal((await pool.query('SELECT count(*) FROM notificacion_entrega')).rows[0].count,'0');
      assert.equal(sends,0);
      assert.deepEqual((await pool.query(`SELECT * FROM reconocimiento_publicacion WHERE fk_avistamiento IN (501,503,504) ORDER BY fk_avistamiento`)).rows,foreignBefore);
      service.stop();restarted.stop();notifications.stop();
    });
    await t.test('out-of-scope enqueue rejects and rolls back its transaction', async()=>{
      await assert.rejects(jobs.transaction(async c=>{
        await c.query("INSERT INTO avistamiento(id,fk_usuario,fk_reporte_perdida,estado) VALUES(505,102,202,'ACTIVO')");
        await jobs.enqueue(c,{sightingId:505,userId:102,requestId:'55555555-5555-4555-8555-555555555555',fingerprint:'e'.repeat(64),shareContact:false});
      }),{code:'RECOGNITION_QA_SCOPE_FORBIDDEN'});
      assert.equal((await pool.query('SELECT count(*) FROM avistamiento WHERE id=505')).rows[0].count,'0');
      assert.equal((await pool.query('SELECT count(*) FROM reconocimiento_publicacion WHERE fk_avistamiento=505')).rows[0].count,'0');
    });
    await t.test('QA disabled preserves global candidates and normal job recovery', async()=>{
      const normal=createRecognitionRepository({pool,qaScope:{mode:false}});
      assert.deepEqual((await normal.activePhotos()).map(p=>p.reportId),[201,202,203]);
      const normalJobs=createMatchRepository({pool,qaScope:{mode:false}});
      assert.equal((await normalJobs.claim()).sightingId,501);
    });
  } finally {
    await client?.close();await pool?.end();
    if(mongoProcess) { mongoProcess.kill(); await new Promise(resolve=>mongoProcess.exitCode!==null?resolve():mongoProcess.once('exit',resolve)); }
    if(started) await control(path.join(pgBin,'pg_ctl.exe'),['-D',pgData,'-m','fast','-w','stop']);
    // Keep temporary logs/data outside Git for inspection; never touch an existing cluster.
  }
});