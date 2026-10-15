require('dotenv').config();

function requiredSecret(name) {
  const value = process.env[name];
  if (!value?.trim()) throw new Error(`Falta la configuración requerida: ${name}`);
  return value;
}

const env = {
  NODE_ENV: process.env.NODE_ENV || 'development',
  PORT: Number(process.env.PORT || 3000),

DB_HOST: process.env.DB_HOST || '127.0.0.1',
DB_PORT: Number(process.env.DB_PORT || 15432),
DB_USER: process.env.DB_USER || 'postgres',
DB_PASSWORD: process.env.DB_PASSWORD,
DB_NAME: process.env.DB_NAME || 'animap',
DB_SSL: process.env.DB_SSL === 'true',

  JWT_ACCESS_SECRET: requiredSecret('JWT_ACCESS_SECRET'),
  JWT_REFRESH_SECRET: requiredSecret('JWT_REFRESH_SECRET'),
  ACCESS_TOKEN_TTL: process.env.ACCESS_TOKEN_TTL || '30m',
  REFRESH_TOKEN_TTL_DAYS: Number(process.env.REFRESH_TOKEN_TTL_DAYS || 7),
  SESSION_IDLE_TIMEOUT_MINUTES: Number(
  process.env.SESSION_IDLE_TIMEOUT_MINUTES || 30
),

  CORS_ORIGIN: process.env.CORS_ORIGIN || '*',
  GEOFENCE_MODE: process.env.GEOFENCE_MODE,
  GOOGLE_GEOCODING_API_KEY: process.env.GOOGLE_GEOCODING_API_KEY,
};

module.exports = env;
