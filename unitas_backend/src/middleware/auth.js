const { verifyAccessToken } = require("../lib/jwt");
const { isUuid } = require("../lib/validate");

function handleJwtError(err, res) {
  if (err.name === "TokenExpiredError") {
    res.status(401).json({ error: "Token sudah kedaluwarsa" });
    return true;
  }
  if (err.name === "JsonWebTokenError" || err.name === "NotBeforeError") {
    res.status(401).json({ error: "Token tidak valid" });
    return true;
  }
  return false;
}

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
    if (handleJwtError(err, res)) return;
    // Misal konfigurasi secret hilang -> 500 lewat error handler
    next(err);
  }
}

/**
 * Parse optional Bearer token on public read routes.
 * Returns `null` when absent, `userId` when valid, or `undefined` after sending 401.
 */
function resolveOptionalViewerId(req, res) {
  const rawAuth = req.headers.authorization;
  if (typeof rawAuth !== "string" || rawAuth.trim() === "") return null;
  const match = /^Bearer\s+(\S+)$/i.exec(rawAuth.trim());
  if (!match) {
    res.status(401).json({ error: "Token tidak valid" });
    return undefined;
  }
  try {
    const decoded = verifyAccessToken(match[1]);
    if (!decoded?.userId || !isUuid(decoded.userId)) {
      res.status(401).json({ error: "Token tidak valid" });
      return undefined;
    }
    return decoded.userId;
  } catch (err) {
    if (handleJwtError(err, res)) return undefined;
    throw err;
  }
}

module.exports = { requireAuth, resolveOptionalViewerId };
