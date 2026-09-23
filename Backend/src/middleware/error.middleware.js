function errorMiddleware(err, req, res, next) {
  const statusCode = err.statusCode || 500;

  if (statusCode >= 500) {
    console.error(err);
  }

  return res.status(statusCode).json({
    ok: false,
    ...(err.code && typeof err.code === 'string' ? { code: err.code } : {}),
    message:
      statusCode === 500 ? 'Error interno del servidor' : err.message,
  });
}

module.exports = errorMiddleware;   
