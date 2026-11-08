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
DB_POOL_MAX: Number(process.env.DB_POOL_MAX || 5),
  TRUST_PROXY_HOPS: process.env.TRUST_PROXY_HOPS === '1' ? 1 : 0,

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
  FCM_PUSH_ENABLED: process.env.FCM_PUSH_ENABLED === 'true',
  FCM_PROCESSING_MODE: process.env.FCM_PROCESSING_MODE || 'inline',
  NOTIFICATION_WORKER_AUDIENCE: process.env.NOTIFICATION_WORKER_AUDIENCE,
  NOTIFICATION_WORKER_SERVICE_ACCOUNT_EMAIL: process.env.NOTIFICATION_WORKER_SERVICE_ACCOUNT_EMAIL,
  FCM_TEST_MODE: process.env.FCM_TEST_MODE ?? 'false',
  FCM_TEST_OWNER_ID: process.env.FCM_TEST_OWNER_ID,
  FCM_TEST_REPORT_ID: process.env.FCM_TEST_REPORT_ID,
};

module.exports = env;
