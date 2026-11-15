const test = require('node:test');
const assert = require('node:assert/strict');
const { createRecognitionRepository } = require('../src/modules/recognition/recognition.repository');
const { createRecognitionService } = require('../src/modules/recognition/recognition.service');
const { createMatchRepository } = require('../src/modules/recognition/recognition.matches.repository');
const scope = { mode: true, testMode: true, ownerId: 101, reportId: 201, reporterId: 102 };

test('QA invalid settings stop recognition before SQL, MongoDB or model access', async () => {
  for (const invalid of [ { ...scope, ownerId: undefined }, { ...scope, reportId: '0' },
    { ...scope, reporterId: undefined }, { ...scope, reporterId: 101 },
    { ...scope, testMode: false }, { ...scope, mode: 'TRUE' },
    { ...scope, reportId: '201 OR 1=1' }, { ...scope, ownerId: 2147483648 } ]) {
    let accesses = 0;
    const repo = createRecognitionRepository({ qaScope: invalid,
      pool: { query: async () => { accesses++; return { rows: [] }; } },
      mongo: async () => { accesses++; throw Error('Unexpected Mongo access'); } });
    const service = createRecognitionService({ repo, worker: {
      request: async () => { accesses++; return { queryId: 'synthetic-query' }; }, close() {} } });
    await assert.rejects(service.search(Buffer.from('synthetic')), { code: 'RECOGNITION_QA_NOT_CONFIGURED' });
    assert.equal(accesses, 0);
    const jobs = createMatchRepository({ qaScope: invalid, pool: { query: async () => { accesses++; return { rows: [] }; } } });
    await assert.rejects(jobs.claim(), { code: 'RECOGNITION_QA_NOT_CONFIGURED' });
    assert.equal(accesses, 0);
  }
});

test('QA refuses out-of-scope Mongo images even when passed directly to repository', async () => {
  let reads = 0;
  const repo = createRecognitionRepository({ qaScope: scope,
    mongo: async () => { reads++; throw Error('Private photo must not be read'); } });
  for (const photo of [{ reportId: 999, ownerId: 101 }, { reportId: 201, ownerId: 999 }]) {
    assert.equal(await repo.photoBytes({ ...photo, petId: 1, photoId: '507f1f77bcf86cd799439011' }), null);
  }
  assert.equal(reads, 0);
});

test('QA refuses publication requests from a different authenticated author before SQL', async () => {
  let queries = 0;
  const jobs = createMatchRepository({ qaScope: scope, pool: { query: async () => { queries++; return { rows: [] }; } } });
  await assert.rejects(jobs.findRequest(jobs.pool, 999, '11111111-1111-4111-8111-111111111111'),
    { code: 'RECOGNITION_QA_SCOPE_FORBIDDEN' });
  assert.equal(queries, 0);
});

test('disabled QA preserves the global HU033 catalogue even with empty QA IDs', async () => {
  const photos = [{ reportId: 201, ownerId: 101 }, { reportId: 999, ownerId: 999 }];
  const repo = createRecognitionRepository({ qaScope: { mode: false },
    pool: { query: async () => ({ rows: photos }) } });
  assert.deepEqual(await repo.activePhotos(), photos);
});
