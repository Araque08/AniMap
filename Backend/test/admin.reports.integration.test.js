const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const db = require('../src/config/postgres_db');
const app = require('../src/app');
const { signAccessToken } = require('../src/utils/jwt');
const { createAdminReportsService } = require('../src/modules/admin-reports/admin-reports.service');
const { createDuplicateReportsService } = require('../src/modules/admin-reports/admin-reports.duplicates.service');
const { confirmSightingDuplicate } = require('../src/modules/admin-reports/admin-reports.deletion.service');
require('../test-support/auth-fixture.cjs').installAuthFixture({ 1: 'USUARIO', 2: 'ADMINISTRADOR' });

const result = rows => ({ rows, rowCount: rows.length });
function candidate(overrides = {}) {
  return { id1: 5, id2: 6, user1Id: 7, user2Id: 7, linkedReport1: 8, linkedReport2: 8,
    description1: 'Perro cafe junto al parque', description2: 'Perro cafe junto al parque',
    lat1: 4.65, lng1: -74.11, lat2: 4.65, lng2: -74.11, minutesDifference: 0,
    created1: '2026-11-01T12:00:00Z', created2: '2026-11-01T12:00:00Z', ...overrides };
}

test('todas las nuevas rutas exigen JWT y ADMINISTRADOR, sin ejecutar consultas de negocio', async t => {
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  const token = signAccessToken({ sub: 1, deviceId: 'test-device', role: 'ADMINISTRADOR' });
  for (const [method, path] of [['GET','/api/admin/reports'],['GET','/api/admin/reports/71'],
    ['GET','/api/admin/reports/duplicates'],['POST','/api/admin/reports/duplicates/confirm'],
    ['PATCH','/api/admin/reports/71/status'],['GET','/api/admin/bitacora']]) {
    assert.equal((await fetch(base + path, {method})).status, 401);
    assert.equal((await fetch(base + path, {method, headers:{Authorization:`Bearer ${token}`}})).status, 403);
  }
});

test('listado administrativo parametriza filtros y rechaza estados inválidos', async () => {
  const calls=[];
  const service=createAdminReportsService({query:async(sql,params)=>{calls.push({sql,params});return result([{id:71}]);}});
  assert.deepEqual(await service.listReports({search:"' OR 1=1 --",estado:'ACTIVO'}),[{id:71}]);
  assert.deepEqual(calls[0].params,["%' OR 1=1 --%",'ACTIVO']);
  assert.ok(!calls[0].sql.includes("' OR 1=1"));
  await assert.rejects(service.listReports({estado:'UNKNOWN'}), e=>e.statusCode===400);
});

test('detalle administrativo no existe: 404', async () => {
  await assert.rejects(createAdminReportsService({query:async()=>result([])}).getReportById(71),e=>e.statusCode===404);
});

test('cerrar un reporte histórico no cambia la mascota con otro reporte ACTIVO', async () => {
  const calls=[];
  const client={release(){},async query(sql,params){calls.push({sql,params});
    if(sql.includes('SELECT fk_mascota'))return result([{fk_mascota:9}]);
    if(sql.includes('FROM mascota'))return result([{id:9,estado:'PERDIDA'}]);
    if(sql.includes('SELECT id, fk_mascota, estado'))return result([{id:71,fk_mascota:9,estado:'FINALIZADO'}]);
    if(sql.includes("AND estado = 'ACTIVO'"))return result([{id:72}]);
    if(sql.includes('UPDATE reporte'))return result([{id:71,estado:'FINALIZADO'}]);
    return result([]);
  }};
  const service=createAdminReportsService({connect:async()=>client});
  await assert.rejects(service.updateReportStatus(71,{estadoReporte:'FINALIZADO',estadoMascota:'ACTIVA'},2),e=>e.statusCode===409);
  assert.ok(!calls.some(c=>/UPDATE mascota/.test(c.sql)));
  assert.ok(calls.some(c=>c.sql==='ROLLBACK'));
});

test('cambio administrativo válido confirma estados y auditoría en una transacción', async () => {
  const calls=[];
  const client={release(){calls.push('release');},async query(sql,params){calls.push(sql);
    if(sql.includes('SELECT fk_mascota'))return result([{fk_mascota:9}]);
    if(sql.includes('FROM mascota'))return result([{id:9,estado:'PERDIDA'}]);
    if(sql.includes('SELECT id, fk_mascota, estado'))return result([{id:71,fk_mascota:9,estado:'ACTIVO'}]);
    if(sql.includes("AND estado = 'ACTIVO'"))return result([]);
    if(sql.includes('UPDATE reporte'))return result([{id:71,estado:'FINALIZADO'}]);
    return result([]);
  }};
  await createAdminReportsService({connect:async()=>client}).updateReportStatus(71,{estadoReporte:'FINALIZADO',estadoMascota:'ACTIVA'},2);
  assert.ok(calls.some(sql=>sql.includes('INSERT INTO bitacora_administrativa')));
  assert.ok(calls.indexOf('COMMIT')>calls.findIndex(sql=>sql.includes('UPDATE mascota')));
  assert.equal(calls.at(-1),'release');
});

test('duplicados descarta coordenadas ausentes y mantiene candidatos válidos', async () => {
  const good=createDuplicateReportsService({query:async()=>result([candidate()])});
  assert.equal((await good.findSightingDuplicates()).length,1);
  const missing=createDuplicateReportsService({query:async()=>result([candidate({lat1:null,lng1:null,lat2:null,lng2:null})])});
  assert.equal((await missing.findSightingDuplicates()).length,0);
});

for(const failure of [null,'audit','duplicate']) {
  test(`confirmación de duplicado: ${failure || 'éxito'} conserva datos y aplica transacción`, async t=>{
    const original=db.pool.connect; const calls=[];
    const client={release(){calls.push({sql:'release'});},async query(sql,params){calls.push({sql,params});
      if(sql.includes('SELECT id, fk_usuario, estado'))return result([{id:5,fk_usuario:7,estado:null},{id:6,fk_usuario:8,estado:null}]);
      if(sql.includes('a1.id AS'))return result([candidate()]);
      if(sql.includes('INSERT INTO revision_duplicados'))return result(failure==='duplicate'?[]:[{id:11}]);
      if(sql.includes('INSERT INTO bitacora_administrativa') && failure==='audit')throw Error('mock audit failure');
      return result([]);
    }};
    db.pool.connect=async()=>client; t.after(()=>{db.pool.connect=original;});
    const action=confirmSightingDuplicate({registro1Id:6,registro2Id:5,conservarId:5,adminId:2,motivo:'Descripción de duplicado confirmada'});
    if(failure) {await assert.rejects(action);assert.ok(calls.some(c=>c.sql==='ROLLBACK'));assert.ok(!calls.some(c=>c.sql==='COMMIT'));}
    else {const value=await action;assert.equal(value.registroEliminado,6);assert.ok(calls.some(c=>c.sql.includes('UPDATE avistamiento')&&c.params[0]===6));assert.ok(calls.some(c=>c.sql.includes('INSERT INTO notificacion')));assert.ok(calls.some(c=>c.sql==='COMMIT'));}
    assert.ok(!calls.some(c=>/DELETE\s+FROM|UPDATE mascota|UPDATE usuario|foto_avistamiento/i.test(c.sql)));
    assert.equal(calls.at(-1).sql,'release');
  });
}

test('bitácora valida fechas/paginación y solo consulta bajo rol vigente', async t=>{
  const original=db.query;
  const queries=[];
  db.query=async(sql,params)=>{
    if(sql.includes('FROM bitacora_administrativa')){queries.push({sql,params});return sql.includes('COUNT(*)')?result([{total:1}]):result([{id:1,modulo:'REPORTES',accion:'EDITAR'}]);}
    return original(sql,params);
  };
  const server=app.listen(0,'127.0.0.1');await once(server,'listening');
  t.after(async()=>{db.query=original;await new Promise(r=>server.close(r));});
  const headers={Authorization:`Bearer ${signAccessToken({sub:2,deviceId:'test-device',role:'ADMINISTRADOR'})}`};
  const base=`http://127.0.0.1:${server.address().port}/api/admin/bitacora`;
  assert.equal((await fetch(base+'?desde=2026-02-31',{headers})).status,400);
  assert.equal((await fetch(base+'?limite=101',{headers})).status,400);
  const response=await fetch(base+'?modulo=REPORTES&desde=2026-11-01&pagina=1',{headers});
  assert.equal(response.status,200);assert.equal((await response.json()).data[0].id,1);
  assert.ok(queries.every(c=>!c.sql.includes('UPDATE')&&!c.sql.includes('DELETE')));
  assert.equal(queries[1].params.at(-2),20);
});

test('mapa combina filtros parametrizados con exclusion de eliminados', async t => {
  const original=db.query; const calls=[];
  db.query=async(sql,params)=>{calls.push({sql,params});return result([]);};
  const server=app.listen(0,'127.0.0.1');await once(server,'listening');
  t.after(async()=>{db.query=original;await new Promise(r=>server.close(r));});
  const response=await fetch('http://127.0.0.1:'+server.address().port+'/api/map/reports?species=perro&color=cafe&from=2026-10-01&to=2026-11-01&status=active');
  assert.equal(response.status,200);
  const sighting=calls.find(c=>c.sql.includes('FROM avistamiento a'));
  assert.ok(sighting);assert.match(sighting.sql,/a.estado IS DISTINCT FROM 'ELIMINADO'/);
  assert.match(sighting.sql,/LOWER\(BTRIM\(e.nombre\)\) = \$1/);
  assert.match(sighting.sql,/a.fecha_hora >=/);
  assert.deepEqual(sighting.params,['perro','cafe','2026-10-01','2026-11-01']);
});

test('detalle, foto e historial excluyen avistamientos eliminados antes de consultar Mongo',async()=>{
  const {createSightingsService}=require('../src/modules/sightings/sightings.service');
  const calls=[];let mongoCalls=0;
  const pool={query:async(sql,params)=>{calls.push({sql,params});return result([]);}};
  const service=createSightingsService(pool,{findPublicSightingImage:async()=>{mongoCalls++;}});
  await assert.rejects(service.getPublicSighting(5),e=>e.statusCode===404);
  await assert.rejects(service.getPublicImage('507f1f77bcf86cd799439011'),e=>e.statusCode===404);
  await assert.rejects(service.getReportHistory(7,71),e=>e.statusCode===404);
  assert.equal(mongoCalls,0);
  assert.ok(calls.every(c=>c.sql.includes("a.estado IS DISTINCT FROM 'ELIMINADO'")));
  assert.match(calls[2].sql,/total_a.estado IS DISTINCT FROM 'ELIMINADO'/);
});

test('FCM no recupera eventos de avistamientos eliminados',async()=>{
  const {createNotificationsRepository}=require('../src/modules/notifications/notifications.repository');
  let sql='';const pool={query:async(text)=>{sql=text;return result([]);}};
  assert.equal(await createNotificationsRepository(pool).loadEvent(pool,5),null);
  assert.match(sql,/a.estado IS DISTINCT FROM 'ELIMINADO'/);
});
