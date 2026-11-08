const env = require('./env');
const { Pool } = require('pg');

const pool = new Pool({
  host: env.DB_HOST,
  port: env.DB_PORT,
  database: env.DB_NAME,
  user: env.DB_USER,
  password: env.DB_PASSWORD,
  ssl: env.DB_SSL ? { rejectUnauthorized: false } : false,
  max: env.DB_POOL_MAX,
  connectionTimeoutMillis: 5000,
  idleTimeoutMillis: 30000,
  query_timeout: 15000,
});

pool.on('error', () => {
  console.error('PostgreSQL: conexión del pool no disponible.');
});

module.exports = {
  pool,
  query: (text, params) => pool.query(text, params),
};
