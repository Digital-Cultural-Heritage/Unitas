function errorHandler(err, req, res, next) {
  if (res.headersSent) return next(err);

  const status = Number(err.status || err.statusCode) || 500;
  const isServerError = status >= 500;

  if (isServerError) {
    console.error("[Error]", req.method, req.originalUrl, err.stack || err.message);
  }

  // Jangan bocorkan detail internal (mis. pesan Supabase/SQL) pada error 5xx
  let message;
  if (isServerError) {
    message =
      process.env.NODE_ENV === "production"
        ? "Terjadi kesalahan pada server"
        : err.message || "Terjadi kesalahan pada server";
  } else if (err.type === "entity.parse.failed") {
    message = "Body JSON tidak valid";
  } else if (err.type === "entity.too.large") {
    message = "Ukuran request terlalu besar";
  } else {
    message = err.message || "Permintaan tidak valid";
  }

  res.status(status).json({ error: message });
}

module.exports = { errorHandler };
