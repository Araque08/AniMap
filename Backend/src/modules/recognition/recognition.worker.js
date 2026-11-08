const { spawn } = require('node:child_process');
const path = require('node:path');
const failure = code => Object.assign(new Error(code), { code });

class RecognitionWorker {
  constructor({ spawnProcess = spawn, timeoutMs = 35000,
    python = process.env.RECOGNITION_PYTHON || path.resolve(__dirname,
      '../../../../Reconocimiento/.venv', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python') } = {}) {
    Object.assign(this, { spawnProcess, python, timeoutMs });
    this.pending = new Map(); this.sequence = 0; this.child = null;
  }
  start() {
    if (this.child) return;
    const env = { PYTHONUNBUFFERED: '1' };
    // Never pass database, SMTP, JWT or Firebase secrets to the model process.
    for (const key of ['SystemRoot', 'SYSTEMROOT', 'PATH', 'USERPROFILE', 'HOME', 'TEMP', 'TMP', 'TORCH_HOME']) {
      if (process.env[key]) env[key] = process.env[key];
    }
    const child = this.spawnProcess(this.python,
      ['-u', path.resolve(__dirname, '../../../../Reconocimiento/worker.py')],
      { shell: false, windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'], env });
    this.child = child;
    let buffer = '';
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', chunk => {
      if (this.child !== child) return;
      buffer += chunk;
      if (buffer.length > 65536) return this.reset('RECOGNITION_UNAVAILABLE');
      let end;
      while ((end = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
        let value;
        try { value = JSON.parse(line); } catch (_) { this.reset(); return; }
        if (value.ready === true && value.model === 'resnet50-imagenet1k-v2') continue;
        const pending = this.pending.get(value.id);
        if (!pending) { this.reset(); return; }
        pending.finish(value.error ? failure(value.error === 'INVALID_IMAGE'
          ? 'INVALID_RECOGNITION_IMAGE' : 'RECOGNITION_UNAVAILABLE') : null, value);
      }
    });
    const lost = () => { if (this.child === child) this.reset(); };
    child.on('error', lost); child.on('exit', lost); child.stdin.on('error', lost);
  }
  request(action, payload = {}, { signal, timeoutMs = this.timeoutMs } = {}) {
    if (signal?.aborted) return Promise.reject(failure('RECOGNITION_TIMEOUT'));
    try { this.start(); } catch (_) { return Promise.reject(failure('RECOGNITION_UNAVAILABLE')); }
    const child = this.child;
    const id = String(++this.sequence);
    return new Promise((resolve, reject) => {
      const abort = () => this.reset('RECOGNITION_TIMEOUT');
      const timer = setTimeout(abort, timeoutMs);
      const finish = (error, value) => {
        clearTimeout(timer); signal?.removeEventListener('abort', abort); this.pending.delete(id);
        if (error) reject(error); else resolve(value);
      };
      this.pending.set(id, { finish });
      signal?.addEventListener('abort', abort, { once: true });
      try {
        child.stdin.write(JSON.stringify({ id, action, ...payload }) + '\n', error => {
          if (error && this.child === child) this.reset();
        });
      } catch (_) { if (this.child === child) this.reset(); }
    });
  }
  reset(code = 'RECOGNITION_UNAVAILABLE') {
    const child = this.child; this.child = null;
    for (const pending of [...this.pending.values()]) pending.finish(failure(code));
    child?.kill();
  }
  close() { this.reset(); }
}
const recognitionWorker = new RecognitionWorker();
process.once('exit', () => recognitionWorker.close());
module.exports = { RecognitionWorker, recognitionWorker, failure };
