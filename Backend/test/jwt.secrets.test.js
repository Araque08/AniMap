const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { tmpdir } = require('node:os');

const envModule = require.resolve('../src/config/env');

function loadConfigWith(accessSecret, refreshSecret) {
  const verify = `const config = require(process.argv[1]);
    if (config.JWT_ACCESS_SECRET !== process.env.JWT_ACCESS_SECRET ||
        config.JWT_REFRESH_SECRET !== process.env.JWT_REFRESH_SECRET) process.exit(2);`;
  return spawnSync(process.execPath, ['-e', verify, envModule], {
    cwd: tmpdir(),
    env: {
      ...process.env,
      JWT_ACCESS_SECRET: accessSecret,
      JWT_REFRESH_SECRET: refreshSecret,
    },
    encoding: 'utf8',
  });
}

test('el arranque rechaza JWT_ACCESS_SECRET ausente sin revelar credenciales', () => {
  const result = loadConfigWith('', 'refresh-test-only');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /JWT_ACCESS_SECRET/);
  assert.doesNotMatch(result.stderr, /refresh-test-only/);
});

test('el arranque rechaza JWT_REFRESH_SECRET ausente sin revelar credenciales', () => {
  const result = loadConfigWith('access-test-only', '');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /JWT_REFRESH_SECRET/);
  assert.doesNotMatch(result.stderr, /access-test-only/);
});

test('el arranque acepta ambos secretos configurados', () => {
  const result = loadConfigWith(' access-test-only ', 'refresh-test-only');
  assert.equal(result.status, 0);
});
