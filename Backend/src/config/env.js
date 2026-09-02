require('dotenv').config();

const env = {
  NODE_ENV: process.env.NODE_ENV || 'development',
  PORT: Number(process.env.PORT || 3000),

DB_HOST: process.env.DB_HOST || '127.0.0.1',
DB_PORT: Number(process.env.DB_PORT || 15432),
DB_USER: process.env.DB_USER || 'postgres',
DB_PASSWORD: process.env.DB_PASSWORD || 'e]F~tly|{&/.$Mud',
DB_NAME: process.env.DB_NAME || 'animap',
DB_SSL: process.env.DB_SSL === 'true',

  JWT_ACCESS_SECRET: process.env.JWT_ACCESS_SECRET || 'access-dev-secret',
  JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET || 'refresh-dev-secret',
  ACCESS_TOKEN_TTL: process.env.ACCESS_TOKEN_TTL || '30m',
  REFRESH_TOKEN_TTL_DAYS: Number(process.env.REFRESH_TOKEN_TTL_DAYS || 7),

  CORS_ORIGIN: process.env.CORS_ORIGIN || '*',
};

module.exports = env;