function validateBody(schema) {
  return (req, res, next) => {
    const result = schema.safeParse(req.body);

    if (!result.success) {
      return res.status(400).json({
        ok: false,
        message: 'Datos inválidos',
        errors: result.error.issues.map((issue) => ({
          field: issue.path.join('.'),
          message: issue.message,
        })),
      });
    }

    req.validatedBody = result.data;
    next();
  };
}

module.exports = validateBody;