// Preload for mock-only runs: fail closed if a test reaches a real database.
require('./env.cjs');
process.env.DOTENV_CONFIG_QUIET = 'true';
const { Pool } = require('pg');
const { MongoClient } = require('mongodb');
Pool.prototype.connect = function (callback) {
  const error = new Error('Real PostgreSQL connections disabled in isolated tests');
  if (callback) return callback(error);
  return Promise.reject(error);
};
MongoClient.prototype.connect = async function () {
  throw new Error('Real MongoDB connections disabled in isolated tests');
};
