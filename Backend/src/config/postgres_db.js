const env = require('./env');

const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

pool.on('error', (error) => {
  console.error('PostgreSQL pool error:', error);
});

module.exports = {
  pool,
  query: (text, params) => pool.query(text, params),
};