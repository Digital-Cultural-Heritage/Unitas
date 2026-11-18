// Shared request helpers: pagination, UUID validation, search sanitising.

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isUuid(value) {
  return typeof value === "string" && UUID_RE.test(value);
}

/**
 * Express router.param handler: reject malformed UUIDs with 404 instead of
 * letting Postgres raise a 22P02 error (-> 500) or letting the value be
 * interpolated into a PostgREST `or()` filter string (filter injection).
 */
function uuidParam(req, res, next, value) {
  if (!isUuid(value)) return res.status(404).json({ error: "Data tidak ditemukan" });
  next();
}

/** Clamp page/limit query values to sane bounds. */
function parsePagination(query, { defaultLimit = 20, maxLimit = 50 } = {}) {
  let page = parseInt(query.page, 10);
  let limit = parseInt(query.limit, 10);
  if (!Number.isFinite(page) || page < 1) page = 1;
  if (page > 10000) page = 10000;
  if (!Number.isFinite(limit) || limit < 1) limit = defaultLimit;
  if (limit > maxLimit) limit = maxLimit;
  const offset = (page - 1) * limit;
  return { page, limit, offset, to: offset + limit - 1 };
}

/**
 * Make a free-text search term safe for use inside a PostgREST `or()` /
 * `ilike` filter: strip characters that carry filter-syntax meaning and
 * LIKE wildcards, and cap the length.
 */
function sanitizeSearch(q) {
  if (typeof q !== "string") return "";
  return q
    .replace(/[,()*%_\\"'`:;]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 60);
}

/** Trimmed string or undefined when not a string. */
function str(value) {
  return typeof value === "string" ? value.trim() : undefined;
}

/** True for http(s) URLs only (blocks javascript:, data:, etc.). */
function isHttpUrl(value) {
  if (typeof value !== "string" || value.length > 2048) return false;
  try {
    const u = new URL(value);
    return u.protocol === "http:" || u.protocol === "https:";
  } catch (_) {
    return false;
  }
}

/** Postgres unique-violation / foreign-key-violation helpers. */
const isUniqueViolation = (err) => !!err && err.code === "23505";
const isFkViolation = (err) => !!err && err.code === "23503";

module.exports = {
  isUuid,
  uuidParam,
  parsePagination,
  sanitizeSearch,
  str,
  isHttpUrl,
  isUniqueViolation,
  isFkViolation,
};
