const bcrypt = require('bcrypt');

const SALT_ROUNDS = 12;

async function hashText(value) {
  return bcrypt.hash(value, SALT_ROUNDS);
}

async function compareHash(plainValue, hashedValue) {
  return bcrypt.compare(plainValue, hashedValue);
}

module.exports = {
  hashText,
  compareHash,
};