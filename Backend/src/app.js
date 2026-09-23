const express = require('express');
const helmet = require('helmet');
const cors = require('cors');

const routes = require('./routes');
const errorMiddleware = require('./middleware/error.middleware');

const app = express();

app.disable('x-powered-by');

app.use(helmet());
app.use(cors({ origin: true, credentials: true }));

app.use(express.json({ limit: '10kb', strict: true }));
app.use(express.urlencoded({ extended: false, limit: '10kb' }));

app.use('/api', routes);

app.use(errorMiddleware);

module.exports = app;
