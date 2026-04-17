const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');

const routes = require('./routes');
const errorMiddleware = require('./middleware/error.middleware');

const app = express();

app.disable('x-powered-by');

app.use(helmet());
app.use(cors({ origin: true, credentials: true }));

app.use(express.json({ limit: '10kb', strict: true }));
app.use(express.urlencoded({ extended: false, limit: '10kb' }));

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: {
    ok: false,
    message: 'Demasiados intentos. Intenta más tarde.',
  },
});

app.use('/api/auth', authLimiter);
app.use('/api', routes);

app.use(errorMiddleware);

module.exports = app;