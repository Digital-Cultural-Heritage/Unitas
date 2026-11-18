const crypto = require("crypto");
const jwt = require("jsonwebtoken");

const ALGORITHMS = ["HS256"];

// Secrets dibaca saat dipakai (bukan saat module load) supaya dotenv/env test
// sudah terisi, dan error konfigurasi jelas alih-alih "secretOrPrivateKey must have a value".
function secret(name) {
  const value = process.env[name];
  if (!value) {
    const err = new Error(`Konfigurasi server belum lengkap (${name})`);
    err.status = 500;
    throw err;
  }
  return value;
}

const accessExpires = () => process.env.JWT_EXPIRES_IN || "7d";
const refreshExpires = () => process.env.REFRESH_TOKEN_EXPIRES_IN || "30d";

function signAccessToken(payload) {
  return jwt.sign({ ...payload, typ: "access" }, secret("JWT_SECRET"), {
    algorithm: "HS256",
    expiresIn: accessExpires(),
  });
}

function signRefreshToken(payload) {
  // jti membuat setiap refresh token unik (rotasi di detik yang sama tidak menghasilkan token identik)
  return jwt.sign({ ...payload, typ: "refresh" }, secret("REFRESH_TOKEN_SECRET"), {
    algorithm: "HS256",
    expiresIn: refreshExpires(),
    jwtid: crypto.randomUUID(),
  });
}

function verifyAccessToken(token) {
  const decoded = jwt.verify(token, secret("JWT_SECRET"), { algorithms: ALGORITHMS });
  // Token lama tanpa `typ` tetap diterima; refresh token tidak boleh dipakai sebagai access token
  if (decoded.typ && decoded.typ !== "access") {
    throw new jwt.JsonWebTokenError("invalid token type");
  }
  return decoded;
}

function verifyRefreshToken(token) {
  const decoded = jwt.verify(token, secret("REFRESH_TOKEN_SECRET"), { algorithms: ALGORITHMS });
  if (decoded.typ && decoded.typ !== "refresh") {
    throw new jwt.JsonWebTokenError("invalid token type");
  }
  return decoded;
}

module.exports = {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
};
