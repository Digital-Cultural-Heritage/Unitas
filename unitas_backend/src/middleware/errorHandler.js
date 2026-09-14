function errorHandler(err, req, res, next) {
  console.error("[Error]", err.message, err.stack);

  const status = err.status || err.statusCode || 500;
  const message = err.message || "Terjadi kesalahan pada server";

  res.status(status).json({ error: message });
}

module.exports = { errorHandler };
