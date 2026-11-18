const { verifyAccessToken } = require("../lib/jwt");

function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  const match = typeof authHeader === "string" && /^Bearer\s+(\S+)$/i.exec(authHeader);
  if (!match) {
    return res.status(401).json({ error: "Token tidak ditemukan" });
  }

  try {
    const decoded = verifyAccessToken(match[1]);
    req.user = decoded; // { userId, email, role }
    next();
  } catch (err) {
    if (err.name === "TokenExpiredError") {
      return res.status(401).json({ error: "Token sudah kedaluwarsa" });
    }
    if (err.name === "JsonWebTokenError" || err.name === "NotBeforeError") {
      return res.status(401).json({ error: "Token tidak valid" });
    }
    // Misal konfigurasi secret hilang -> 500 lewat error handler
    next(err);
  }
}

module.exports = { requireAuth };
