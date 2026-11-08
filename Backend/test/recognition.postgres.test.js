const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { spawn, execFile } = require('node:child_process');
const exec = require('node:util').promisify(execFile);
const control = (exe, args) => new Promise((resolve, reject) => {
  const child = spawn(exe, args, { stdio: 'ignore', windowsHide: true });
  child.once('error', reject); child.once('exit', code => code === 0 ? resolve() : reject(Error('Temporary PostgreSQL failed')));
});

// Explicit opt-in. Own cluster/port/role, no .env or Cloud SQL connection.
test('real isolated SQL: all photos of active lost reports, correct owner binding',
  { skip: process.env.ANIMAP_RUN_RECOGNITION_PG !== '1', timeout: 90000 }, async () => {
    const bin = process.env.ANIMAP_TEST_PG_BIN;
    assert.ok(bin);
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'animap79-pg-'));
    const data = path.join(root, 'data');
    const socket = net.createServer(); await new Promise(resolve => socket.listen(0, '127.0.0.1', resolve));
    const port = socket.address().port; await new Promise(resolve => socket.close(resolve));
    let pool, started = false;
    try {
      await exec(path.join(bin, 'initdb.exe'), ['-D', data, '-U', 'animap_test', '-A', 'trust', '--no-locale', '-E', 'UTF8']);
      await control(path.join(bin, 'pg_ctl.exe'), ['-D', data, '-l', path.join(root, 'postgres.log'), '-o', `-h 127.0.0.1 -p ${port} -F`, '-w', 'start']);
      started = true;
      pool = new (require('pg').Pool)({ host: '127.0.0.1', port, user: 'animap_test', database: 'postgres', max: 1 });
      await pool.query(`CREATE TABLE especie(id INTEGER PRIMARY KEY,nombre TEXT);
        CREATE TABLE raza(id INTEGER PRIMARY KEY,nombre TEXT);
        CREATE TABLE mascota(id INTEGER PRIMARY KEY,fk_usuario INTEGER,fk_especie INTEGER,fk_raza INTEGER,nombre TEXT,color TEXT,estado TEXT);
        CREATE TABLE reporte(id INTEGER PRIMARY KEY,fk_mascota INTEGER,fk_usuario INTEGER,estado TEXT);
        CREATE TABLE foto_mascota(id INTEGER PRIMARY KEY,fk_mascota INTEGER,storage_ref TEXT,es_principal BOOLEAN);
        INSERT INTO especie VALUES(1,'Perro'); INSERT INTO raza VALUES(1,'QA');
        INSERT INTO mascota VALUES(11,7,1,1,'QA A','cafe','PERDIDA'),(12,8,1,1,'QA B','negro','ACTIVA'),(13,8,1,1,'QA C','blanco','PERDIDA');
        INSERT INTO reporte VALUES(1,11,7,'ACTIVO'),(2,12,8,'ACTIVO'),(3,13,8,'FINALIZADO'),(4,13,7,'ACTIVO');
        INSERT INTO foto_mascota VALUES(1,11,'photo-a',TRUE),(2,11,'photo-b',FALSE),(3,12,'photo-c',TRUE),(4,13,'photo-d',TRUE);`);
      const repo = require('../src/modules/recognition/recognition.repository').createRecognitionRepository({ pool });
      const result = await repo.activePhotos();
      assert.deepEqual(result.map(p => [p.reportId, p.petId, p.photoId]), [[1,11,'photo-a'],[1,11,'photo-b']]);
    } finally {
      await pool?.end();
      if (started) await control(path.join(bin, 'pg_ctl.exe'), ['-D', data, '-m', 'fast', '-w', 'stop']);
      if (path.dirname(root) === os.tmpdir() && path.basename(root).startsWith('animap79-pg-')) {
        await fs.rm(root, { recursive: true, force: true });
      }
    }
  });
