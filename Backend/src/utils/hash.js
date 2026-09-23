const bcrypt = require('bcrypt');
const { createHash, timingSafeEqual } = require('node:crypto');

const SALT_ROUNDS = 12;

async function hashText(value) {
  return bcrypt.hash(value, SALT_ROUNDS);
}

async function compareHash(plainValue, hashedValue) {
  return bcrypt.compare(plainValue, hashedValue);
}

function hashRefreshToken(value) {
  return `sha256:${createHash('sha256').update(value, 'utf8').digest('hex')}`;
}

async function compareRefreshToken(plainValue, storedHash) {
  if (typeof storedHash !== 'string') return false;
  if (storedHash.startsWith('sha256:')) {
    const calculated = Buffer.from(hashRefreshToken(plainValue), 'utf8');
    const stored = Buffer.from(storedHash, 'utf8');
    return calculated.length === stored.length && timingSafeEqual(calculated, stored);
  }
  // Compatibilidad transitoria con sesiones creadas antes del cambio.
  if (storedHash.startsWith('$2')) return compareHash(plainValue, storedHash);
  return false;
}

module.exports = {
  hashText,
  compareHash,
  hashRefreshToken,
  compareRefreshToken,
};
