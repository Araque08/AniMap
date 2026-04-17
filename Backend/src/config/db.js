const { Pool } = require('pg');
const env = require('./env');

const pool = new Pool({
  host: env.DB_HOST,
  port: env.DB_PORT,
  user: env.DB_USER,
  password: env.DB_PASSWORD,
  database: env.DB_NAME,
  ssl: env.DB_SSL ? { rejectUnauthorized: false } : false,
});

pool.on('error', (error) => {
  console.error('PostgreSQL pool error:', error);
});

module.exports = {
  pool,
  query: (text, params) => pool.query(text, params),
};