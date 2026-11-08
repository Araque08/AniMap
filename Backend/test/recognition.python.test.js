const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { once } = require('node:events');
const express = require('express');
const { RecognitionWorker } = require('../src/modules/recognition/recognition.worker');
const { createRecognitionService } = require('../src/modules/recognition/recognition.service');
const { createRecognitionRouter } = require('../src/modules/recognition/recognition.routes');

test('real HTTP/JWT -> Node -> persistent Python -> pretrained CPU -> ranked reports',
  { skip: process.env.ANIMAP_RUN_RECOGNITION_REAL !== '1', timeout: 90000 }, async () => {
    const worker = new RecognitionWorker();
    const a = fs.readFileSync('../Reconocimiento/imagenes_prueba/mascota1.jpeg');
    const b = fs.readFileSync('../Reconocimiento/imagenes_prueba/mascota2.jpeg');
    const photos = [{ reportId: 101, petId: 201, photoId: '000000000000000000000001', nombre: 'QA archivo A' },
      { reportId: 102, petId: 202, photoId: '000000000000000000000002', nombre: 'QA archivo B' }];
    const service = createRecognitionService({ worker, repo: {
      activePhotos: async () => photos,
      photoBytes: async p => p.reportId === 101 ? a : b,
    } });
    const restore = require('../test-support/auth-fixture.cjs').installAuthFixture({ 7: 'USUARIO' });
    const app = express(); app.use('/api/recognition', createRecognitionRouter({ service, limiter: (_, __, next) => next() }));
    const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
    const headers = { Authorization: `Bearer ${require('../src/utils/jwt').signAccessToken({ sub: 7, deviceId: 'qa-cpu', role: 'USUARIO' })}` };
    async function search(bytes) {
      const form = new FormData(); form.append('foto', new Blob([bytes], { type: 'image/jpeg' }), 'qa.jpeg');
      return fetch(`http://127.0.0.1:${server.address().port}/api/recognition/search`, { method: 'POST', headers, body: form });
    }
    try {
      const response = await search(a); assert.equal(response.status, 200);
      const result = await response.json();
      assert.equal(result.matches[0].reportId, 101); assert.ok(result.matches[0].similarity > 0.9999);
      assert.equal(result.searchedImages, 2);
      const pid = worker.child.pid;
      assert.equal((await search(a)).status, 200); assert.equal(worker.child.pid, pid);
      assert.equal((await search(Buffer.from([255, 216, 255, 1, 2]))).status, 400);
      console.log('Real CPU scores (unlabeled identities):', result.matches.map(m => ({ reportId: m.reportId, similarity: m.similarity })));
    } finally { restore(); worker.close(); await new Promise(resolve => server.close(resolve)); }
  });
