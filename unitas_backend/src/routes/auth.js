const express = require("express");
const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const validator = require("validator");
const rateLimit = require("express-rate-limit");
const { body, validationResult } = require("express-validator");
const supabase = require("../lib/supabase");
const { signAccessToken, signRefreshToken, verifyRefreshToken } = require("../lib/jwt");
const { requireAuth } = require("../middleware/auth");
const { sendOtpEmail } = require("../lib/mailer");

const router = express.Router();

const BCRYPT_ROUNDS = Number(process.env.BCRYPT_ROUNDS) || 12;
// Hash bcrypt valid untuk menyamakan waktu respons login saat email tidak ditemukan (anti user-enumeration)
const DUMMY_HASH = "$2b$12$R9h/cIPz0gi.URNNX3kh2OPST9/PgBkqquzi.Ss7KIUgO2t0jWMUW";
// Penanda akun tanpa password (mis. dibuat lewat Google). Bukan hash bcrypt valid -> tidak bisa login dengan password.
const NO_PASSWORD = "!no-password";
const OTP_MAX_ATTEMPTS = 5;
const OTP_TTL_MS = 15 * 60 * 1000;
const CAMPUS_EMAIL_ERROR =
  "Hanya email kampus (@unud.ac.id atau @student.unud.ac.id) yang diizinkan";

function allowedEmailDomains() {
  const raw = process.env.ALLOWED_EMAIL_DOMAINS ?? "unud.ac.id,student.unud.ac.id";
  return String(raw)
    .split(",")
    .map((d) => d.trim().toLowerCase())
    .filter(Boolean);
}

function isAllowedCampusEmail(email) {
  if (typeof email !== "string") return false;
  const parts = email.trim().toLowerCase().split("@");
  if (parts.length !== 2 || !parts[0] || !parts[1]) return false;
  return allowedEmailDomains().includes(parts[1]);
}

const pendingEmailOtps = new Map();

function pruneExpiredEmailOtps(now = Date.now()) {
  for (const [k, v] of pendingEmailOtps.entries()) {
    if (!v || v.expiresAt <= now) pendingEmailOtps.delete(k);
  }
}

function issueEmailOtp(email, purpose) {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    const err = new Error("JWT_SECRET belum dikonfigurasi");
    err.status = 500;
    throw err;
  }
  const now = Date.now();
  pruneExpiredEmailOtps(now);
  const otpCode = String(crypto.randomInt(100000, 1000000));
  const digest = otpDigest(`${purpose}:${email}`, otpCode);
  pendingEmailOtps.set(`${purpose}:${email}`, {
    digest,
    expiresAt: now + OTP_TTL_MS,
    attempts: 0,
  });
  const otpToken = jwt.sign(
    { typ: "email_otp", email, purpose, digest },
    secret,
    { algorithm: "HS256", expiresIn: "15m" }
  );
  return { otpCode, otpToken };
}

function verifyEmailOtp({ email, otp, otpToken, purpose }) {
  const code = String(otp || "").trim();
  if (!/^\d{6}$/.test(code)) return false;

  const key = `${purpose}:${email}`;
  const entry = pendingEmailOtps.get(key);
  const now = Date.now();
  if (entry) {
    if (entry.expiresAt <= now) {
      pendingEmailOtps.delete(key);
      return false;
    }
    if (entry.attempts >= OTP_MAX_ATTEMPTS) {
      return false;
    }
  }

  const expected = otpDigest(`${purpose}:${email}`, code);
  if (otpToken && typeof otpToken === "string") {
    try {
      const decoded = jwt.verify(otpToken, process.env.JWT_SECRET || "", {
        algorithms: ["HS256"],
      });
      if (
        !decoded ||
        decoded.typ !== "email_otp" ||
        decoded.purpose !== purpose ||
        decoded.email !== email ||
        !decoded.digest
      ) {
        return false;
      }
      if (!safeEqual(decoded.digest, expected)) {
        if (entry) entry.attempts += 1;
        return false;
      }
      pendingEmailOtps.delete(key);
      return true;
    } catch {
      return false;
    }
  }

  if (!entry) return false;
  if (!safeEqual(entry.digest, expected)) {
    entry.attempts += 1;
    return false;
  }
  pendingEmailOtps.delete(key);
  return true;
}

// ── Rate limiting ────────────────────────────────────────────────────────
// Catatan: di Vercel (serverless) store-nya in-memory per instance, jadi ini
// perlindungan "best effort". Untuk proteksi ketat gunakan Vercel Firewall / Upstash.
function limiter(max, message) {
  return rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: max,
    standardHeaders: "draft-7",
    legacyHeaders: false,
    validate: { trustProxy: false, xForwardedForHeader: false },
    message: { error: message },
  });
}
const authLimiter = () => limiter(60, "Terlalu banyak percobaan, coba lagi beberapa menit lagi");
const otpLimiter = (max = 10) => limiter(max, "Terlalu banyak percobaan, coba lagi beberapa menit lagi");

// ── Helpers ──────────────────────────────────────────────────────────────
function validate(req, res) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    res.status(400).json({ errors: errors.array() });
    return false;
  }
  return true;
}

// Normalisasi sama persis dengan express-validator normalizeEmail() (default),
// supaya email dari Google cocok dengan email yang didaftarkan manual.
function normalizeEmail(email) {
  return validator.normalizeEmail(String(email)) || String(email).toLowerCase();
}

// PostgREST mengembalikan relasi one-to-one sebagai object, one-to-many sebagai array
function firstProfile(rel) {
  if (Array.isArray(rel)) return rel[0] || {};
  return rel || {};
}

function hasPassword(hash) {
  return typeof hash === "string" && hash.startsWith("$2");
}

function tokenPayload(user) {
  return { userId: user.id, email: user.email, role: user.role };
}

function otpDigest(email, otp) {
  const key = process.env.JWT_SECRET || "";
  return crypto.createHmac("sha256", key).update(`${email}:${otp}`).digest("hex");
}

function safeEqual(a, b) {
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  return ba.length === bb.length && crypto.timingSafeEqual(ba, bb);
}

function isMissingColumn(err, col) {
  return Boolean(
    err &&
      (err.code === "42703" ||
        err.code === "PGRST204" ||
        (typeof err.message === "string" && err.message.includes(col)))
  );
}

// Buat access+refresh token & simpan refresh token (1 query). `extra` = kolom tambahan yang ikut di-update.
async function startSession(user, extra = {}) {
  const payload = tokenPayload(user);
  const accessToken = signAccessToken(payload);
  const refreshToken = signRefreshToken(payload);
  let { error } = await supabase
    .from("users")
    .update({ refresh_token: refreshToken, ...extra })
    .eq("id", user.id);
  if (error && Object.keys(extra).length > 0 && isMissingColumn(error, "google_sub")) {
    ({ error } = await supabase
      .from("users")
      .update({ refresh_token: refreshToken })
      .eq("id", user.id));
  }
  if (error) throw error;
  return { accessToken, refreshToken };
}

// Bentuk respons login (dipakai oleh /login dan /google — harus identik)
function sessionResponse({ accessToken, refreshToken }, user, profile) {
  return {
    access_token: accessToken,
    refresh_token: refreshToken,
    user: {
      id: user.id,
      email: user.email,
      role: user.role,
      full_name: profile.full_name ?? null,
      avatar_url: profile.avatar_url ?? null,
    },
  };
}

// ── POST /api/auth/send-otp ───────────────────────────────────────────────
router.post(
  "/send-otp",
  otpLimiter(10),
  [body("email").isEmail().normalizeEmail().withMessage("Email tidak valid")],
  async (req, res, next) => {
    if (!validate(req, res)) return;
    try {
      const { email } = req.body;
      if (!isAllowedCampusEmail(email)) {
        return res.status(400).json({ error: CAMPUS_EMAIL_ERROR });
      }

      const purpose = req.body.purpose === undefined ? "register" : String(req.body.purpose).trim();
      if (purpose !== "register" && purpose !== "login") {
        return res.status(400).json({ error: "Purpose OTP tidak valid" });
      }

      if (purpose === "register") {
        const { data: existing, error } = await supabase
          .from("users")
          .select("id")
          .eq("email", email)
          .maybeSingle();
        if (error) throw error;
        if (existing) return res.status(409).json({ error: "Email sudah terdaftar" });
      } else {
        const password = req.body.password;
        if (typeof password !== "string" || !password) {
          return res.status(400).json({ error: "Password wajib diisi" });
        }
        const { data: user, error } = await supabase
          .from("users")
          .select("id, email, password_hash, role")
          .eq("email", email)
          .maybeSingle();
        if (error) throw error;
        const match = await bcrypt.compare(
          password,
          user && hasPassword(user.password_hash) ? user.password_hash : DUMMY_HASH
        );
        if (!user || !match) return res.status(401).json({ error: "Email atau password salah" });
      }

      const { otpCode, otpToken } = issueEmailOtp(email, purpose);
      let mailResult;
      try {
        mailResult = await sendOtpEmail({ to: email, otpCode, purpose });
      } catch (e) {
        console.error("Send OTP email error:", e.message);
        return res.status(502).json({ error: "Gagal mengirim email OTP. Silakan coba lagi." });
      }

      res.json({
        message: "Kode OTP telah dikirim ke email kamu",
        otp_token: otpToken,
        ...(process.env.NODE_ENV !== "production" && !mailResult.sent ? { dev_otp: otpCode } : {}),
      });
    } catch (err) {
      next(err);
    }
  }
);

// ── POST /api/auth/register ───────────────────────────────────────────────
router.post(
  "/register",
  authLimiter(),
  [
    body("email")
      .isEmail()
      .normalizeEmail()
      .withMessage("Email tidak valid")
      .bail()
      .custom((v) => isAllowedCampusEmail(v))
      .withMessage(CAMPUS_EMAIL_ERROR),
    body("password")
      .isString()
      .isLength({ min: 8 })
      .withMessage("Password minimal 8 karakter")
      .bail()
      .custom((v) => Buffer.byteLength(v, "utf8") <= 72)
      .withMessage("Password maksimal 72 karakter"),
    body("full_name").isString().trim().notEmpty().isLength({ max: 100 }).withMessage("Nama lengkap wajib diisi"),
    body("prodi").isString().trim().notEmpty().isLength({ max: 100 }).withMessage("Program studi wajib diisi"),
    body("angkatan")
      .customSanitizer((v) => (typeof v === "string" || typeof v === "number" ? String(v).trim() : ""))
      .notEmpty()
      .withMessage("Angkatan wajib diisi")
      .isLength({ max: 20 })
      .withMessage("Angkatan maksimal 20 karakter"),
    body("kota").optional({ values: "falsy" }).isString().trim().isLength({ max: 100 }),
  ],
  async (req, res, next) => {
    if (!validate(req, res)) return;
    try {
      const { email, password, full_name, prodi, angkatan, kota, otp, otp_token } = req.body;

      if (!verifyEmailOtp({ email, otp, otpToken: otp_token, purpose: "register" })) {
        return res.status(400).json({ error: "Kode OTP tidak valid atau sudah kedaluwarsa" });
      }

      const password_hash = await bcrypt.hash(password, BCRYPT_ROUNDS);

      // ID dibuat di sisi server agar token bisa dibuat sebelum insert (hemat 1 query update)
      const user = { id: crypto.randomUUID(), email, role: "alumni" };
      const payload = tokenPayload(user);
      const accessToken = signAccessToken(payload);
      const refreshToken = signRefreshToken(payload);

      // Duplikat email ditangani oleh UNIQUE constraint (aman dari race condition)
      const { error: userErr } = await supabase
        .from("users")
        .insert({ id: user.id, email, password_hash, role: user.role, refresh_token: refreshToken });
      if (userErr) {
        if (userErr.code === "23505") return res.status(409).json({ error: "Email sudah terdaftar" });
        throw userErr;
      }

      const { error: profileErr } = await supabase
        .from("user_profiles")
        .insert({ user_id: user.id, full_name, prodi, angkatan, kota: kota || null });
      if (profileErr) {
        // Rollback agar email tidak "terkunci" tanpa profil
        await supabase.from("users").delete().eq("id", user.id);
        throw profileErr;
      }

      res.status(201).json({
        message: "Registrasi berhasil",
        access_token: accessToken,
        refresh_token: refreshToken,
        user: { id: user.id, email: user.email, role: user.role, full_name, avatar_url: null },
      });
    } catch (err) {
      next(err);
    }
  }
);

// ── POST /api/auth/login ──────────────────────────────────────────────────
router.post(
  "/login",
  authLimiter(),
  [
    body("email")
      .isEmail()
      .normalizeEmail()
      .withMessage("Email tidak valid")
      .bail()
      .custom((v) => isAllowedCampusEmail(v))
      .withMessage(CAMPUS_EMAIL_ERROR),
    body("password").isString().notEmpty().withMessage("Password wajib diisi"),
  ],
  async (req, res, next) => {
    if (!validate(req, res)) return;
    try {
      const { email, password } = req.body;

      // Cari user beserta profil
      const { data: user, error } = await supabase
        .from("users")
        .select("id, email, password_hash, role, user_profiles(full_name, avatar_url)")
        .eq("email", email)
        .maybeSingle();
      if (error) throw error;

      // Selalu jalankan bcrypt.compare agar waktu respons tidak membocorkan keberadaan email
      const match = await bcrypt.compare(
        password,
        user && hasPassword(user.password_hash) ? user.password_hash : DUMMY_HASH
      );
      if (!user || !match) return res.status(401).json({ error: "Email atau password salah" });

      const session = await startSession(user);
      res.json(sessionResponse(session, user, firstProfile(user.user_profiles)));
    } catch (err) {
      next(err);
    }
  }
);

// ── GET /api/auth/me ──────────────────────────────────────────────────────
router.get("/me", requireAuth, async (req, res, next) => {
  try {
    const { data: user, error } = await supabase
      .from("users")
      .select(
        "id, email, role, user_profiles(full_name, initials, avatar_url, bio, prodi, angkatan, kota, pekerjaan, perusahaan, linkedin, points, is_online)"
      )
      .eq("id", req.user.userId)
      .maybeSingle();
    if (error) throw error;
    if (!user) return res.status(404).json({ error: "User tidak ditemukan" });

    const profile = firstProfile(user.user_profiles);
    res.json({
      ...profile,
      id: user.id,
      email: user.email,
      role: user.role,
      full_name: profile.full_name ?? null,
      avatar_url: profile.avatar_url ?? null,
    });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/auth/google ─────────────────────────────────────────────────
// Body: { "id_token": "<Google ID token>" } -> respons identik dengan /login
const DEFAULT_GOOGLE_CLIENT_ID =
  "900620974472-q2n23p2jtahugolc13a51ma0plo2pi1n.apps.googleusercontent.com";
let _googleClient;
function googleAudiences() {
  const raw = [
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_SERVER_CLIENT_ID,
    process.env.GOOGLE_SERVER_CLIENT_IDS,
    process.env.GOOGLE_SERVER_CLIENT_IDs,
  ]
    .filter(Boolean)
    .flatMap((v) => String(v).split(","))
    .map((s) => s.trim())
    .filter(Boolean);
  if (raw.length === 0 && process.env.GOOGLE_CLIENT_ID !== "") {
    return [DEFAULT_GOOGLE_CLIENT_ID];
  }
  return [...new Set(raw)];
}

async function verifyGoogleIdToken(idToken, audience) {
  // Lazy-load: library ini tidak dibebani saat cold start endpoint lain
  if (!_googleClient) {
    const { OAuth2Client } = require("google-auth-library");
    _googleClient = new OAuth2Client();
  }
  const ticket = await _googleClient.verifyIdToken({ idToken, audience });
  return ticket.getPayload();
}

const USER_COLS = "id, email, role, google_sub, user_profiles(full_name, avatar_url)";
const USER_COLS_LEGACY = "id, email, role, user_profiles(full_name, avatar_url)";

async function findUserByGoogleOrEmail(sub, email) {
  let { data, error } = await supabase.from("users").select(USER_COLS).eq("google_sub", sub).maybeSingle();
  if (error && isMissingColumn(error, "google_sub")) {
    ({ data, error } = await supabase.from("users").select(USER_COLS_LEGACY).eq("email", email).maybeSingle());
    if (error) throw error;
    return data;
  }
  if (error) throw error;
  if (!data) {
    ({ data, error } = await supabase.from("users").select(USER_COLS).eq("email", email).maybeSingle());
    if (error) throw error;
  }
  return data;
}

async function ensureGoogleProfile(user, email, claims) {
  const profile = firstProfile(user.user_profiles);
  const fallbackName = String(claims.name || email.split("@")[0]).slice(0, 100);
  const picture = claims.picture || null;

  if (!profile.full_name) {
    const { error } = await supabase
      .from("user_profiles")
      .upsert({ user_id: user.id, full_name: fallbackName, avatar_url: picture }, { onConflict: "user_id" });
    if (error) throw error;
    return { full_name: fallbackName, avatar_url: picture };
  }

  if (!profile.avatar_url && picture) {
    const { error } = await supabase
      .from("user_profiles")
      .update({ avatar_url: picture })
      .eq("user_id", user.id);
    if (!error) return { ...profile, avatar_url: picture };
  }
  return profile;
}

router.post(
  "/google",
  authLimiter(),
  [body("id_token").isString().trim().notEmpty().isLength({ max: 8192 }).withMessage("id_token wajib diisi")],
  async (req, res, next) => {
    if (!validate(req, res)) return;
    try {
      const audience = googleAudiences();
      if (audience.length === 0) {
        console.error("[Auth] GOOGLE_CLIENT_ID belum dikonfigurasi");
        return res.status(503).json({ error: "Login Google belum dikonfigurasi di server" });
      }

      let claims;
      try {
        claims = await verifyGoogleIdToken(req.body.id_token, audience);
      } catch {
        return res.status(401).json({ error: "Token Google tidak valid atau sudah kedaluwarsa" });
      }
      if (!claims || !claims.sub || !claims.email) {
        return res.status(401).json({ error: "Token Google tidak valid" });
      }
      if (claims.email_verified !== true) {
        return res.status(403).json({ error: "Email Google belum terverifikasi" });
      }

      const sub = String(claims.sub);
      const email = normalizeEmail(claims.email);
      if (!isAllowedCampusEmail(email)) {
        return res.status(403).json({ error: CAMPUS_EMAIL_ERROR });
      }
      let user = await findUserByGoogleOrEmail(sub, email);
      let profile;
      const extra = {};

      if (!user) {
        const fullName = String(claims.name || email.split("@")[0]).slice(0, 100);
        const created = { id: crypto.randomUUID(), email, role: "alumni" };
        let { error: insErr } = await supabase
          .from("users")
          .insert({ id: created.id, email, password_hash: NO_PASSWORD, role: created.role, google_sub: sub });
        if (insErr && isMissingColumn(insErr, "google_sub")) {
          ({ error: insErr } = await supabase
            .from("users")
            .insert({ id: created.id, email, password_hash: NO_PASSWORD, role: created.role }));
        }

        if (!insErr) {
          const { error: pErr } = await supabase.from("user_profiles").insert({
            user_id: created.id,
            full_name: fullName,
            avatar_url: claims.picture || null,
          });
          if (pErr) {
            await supabase.from("users").delete().eq("id", created.id);
            throw pErr;
          }
          user = created;
          profile = { full_name: fullName, avatar_url: claims.picture || null };
        } else {
          if (insErr.code !== "23505") throw insErr;
          // Race: request Google paralel membuat user yang sama -> pakai yang sudah ada
          user = await findUserByGoogleOrEmail(sub, email);
          if (!user) throw insErr;
        }
      }

      if (!profile) {
        if (user.google_sub && user.google_sub !== sub) {
          return res.status(409).json({ error: "Email ini sudah terhubung dengan akun Google lain" });
        }
        if (!user.google_sub) extra.google_sub = sub; // tautkan akun email yang sudah ada
        profile = await ensureGoogleProfile(user, email, claims);
      }

      const session = await startSession(user, extra);
      res.json(sessionResponse(session, user, profile));
    } catch (err) {
      next(err);
    }
  }
);

// ── POST /api/auth/refresh ────────────────────────────────────────────────
router.post("/refresh", authLimiter(), async (req, res, next) => {
  try {
    const refresh_token = req.body && req.body.refresh_token;
    if (!refresh_token || typeof refresh_token !== "string") {
      return res.status(400).json({ error: "Refresh token wajib diisi" });
    }

    let decoded;
    try {
      decoded = verifyRefreshToken(refresh_token);
    } catch (e) {
      if (e.status === 500) throw e;
      return res.status(401).json({ error: "Refresh token tidak valid atau sudah kedaluwarsa" });
    }

    // Validasi token di DB
    const { data: user, error } = await supabase
      .from("users")
      .select("id, email, role, refresh_token")
      .eq("id", decoded.userId)
      .maybeSingle();
    if (error) throw error;

    if (!user || !user.refresh_token || !safeEqual(user.refresh_token, refresh_token)) {
      return res.status(401).json({ error: "Refresh token tidak cocok" });
    }

    const payload = tokenPayload(user);
    const newAccessToken = signAccessToken(payload);
    const newRefreshToken = signRefreshToken(payload);

    // Rotasi atomik: hanya berhasil jika refresh token di DB masih sama (cegah dipakai dua kali)
    const { data: rotated, error: updErr } = await supabase
      .from("users")
      .update({ refresh_token: newRefreshToken })
      .eq("id", user.id)
      .eq("refresh_token", refresh_token)
      .select("id");
    if (updErr) throw updErr;
    if (!rotated || rotated.length === 0) {
      return res.status(401).json({ error: "Refresh token tidak cocok" });
    }

    res.json({ access_token: newAccessToken, refresh_token: newRefreshToken });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/auth/logout ─────────────────────────────────────────────────
router.post("/logout", async (req, res, next) => {
  try {
    const refresh_token = req.body && req.body.refresh_token;
    if (refresh_token && typeof refresh_token === "string") {
      const { error } = await supabase
        .from("users")
        .update({ refresh_token: null })
        .eq("refresh_token", refresh_token);
      if (error) throw error;
    }
    res.json({ message: "Logout berhasil" });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/auth/change-password ────────────────────────────────────────
router.post(
  "/change-password",
  requireAuth,
  otpLimiter(10),
  [
    body("current_password").isString().notEmpty().withMessage("Password saat ini wajib diisi"),
    body("new_password")
      .isString()
      .isLength({ min: 8 })
      .withMessage("Password baru minimal 8 karakter")
      .bail()
      .custom((v) => Buffer.byteLength(v, "utf8") <= 72)
      .withMessage("Password baru maksimal 72 karakter"),
  ],
  async (req, res, next) => {
    if (!validate(req, res)) return;
    try {
      const { current_password, new_password } = req.body;
      const { data: user, error } = await supabase
        .from("users")
        .select("id, password_hash")
        .eq("id", req.user.userId)
        .maybeSingle();
      if (error) throw error;
      if (!user) return res.status(404).json({ error: "User tidak ditemukan" });

      if (!hasPassword(user.password_hash)) {
        return res.status(400).json({
          error: "Akun ini masuk dengan Google dan belum punya password. Gunakan 'Lupa password' untuk membuatnya.",
        });
      }

      const match = await bcrypt.compare(current_password, user.password_hash);
      if (!match) return res.status(401).json({ error: "Password saat ini salah" });

      const password_hash = await bcrypt.hash(new_password, BCRYPT_ROUNDS);
      // Cabut refresh token lama agar sesi di perangkat lain berakhir
      const { error: updErr } = await supabase
        .from("users")
        .update({ password_hash, refresh_token: null })
        .eq("id", user.id);
      if (updErr) throw updErr;

      res.json({ message: "Password berhasil diubah" });
    } catch (err) {
      next(err);
    }
  }
);

// ── POST /api/auth/forgot-password ────────────────────────────────────────
router.post(
  "/forgot-password",
  otpLimiter(10),
  [
    body("email")
      .isEmail()
      .normalizeEmail()
      .withMessage("Email tidak valid")
      .bail()
      .custom((v) => isAllowedCampusEmail(v))
      .withMessage(CAMPUS_EMAIL_ERROR),
  ],
  async (req, res, next) => {
    if (!validate(req, res)) return;
    try {
      const { email } = req.body;
      const { data: user, error } = await supabase
        .from("users")
        .select("id, email")
        .eq("email", email)
        .maybeSingle();
      if (error) throw error;

      // Always return generic success to avoid leaking registered emails
      if (!user) {
        return res.json({ message: "Jika email terdaftar, kode OTP telah dikirim" });
      }

      const otpCode = String(crypto.randomInt(100000, 1000000));
      const expiresAt = new Date(Date.now() + OTP_TTL_MS).toISOString();

      // Batalkan OTP lama yang belum dipakai (hanya OTP terbaru yang berlaku)
      const { error: invErr } = await supabase
        .from("password_reset_otps")
        .update({ used: true })
        .eq("user_id", user.id)
        .eq("used", false);
      if (invErr) throw invErr;

      // OTP disimpan sebagai HMAC, bukan plaintext
      const { error: insErr } = await supabase.from("password_reset_otps").insert({
        user_id: user.id,
        email: user.email,
        otp_code: otpDigest(user.email, otpCode),
        expires_at: expiresAt,
      });
      if (insErr) throw insErr;

      let mailResult = { sent: false };
      try {
        mailResult = await sendOtpEmail({ to: user.email, otpCode, purpose: "reset" });
      } catch (e) {
        console.error("Send OTP email error:", e.message);
      }

      const payload = { message: "Jika email terdaftar, kode OTP telah dikirim" };
      if (process.env.NODE_ENV !== "production" && !mailResult.sent) {
        payload.dev_otp = otpCode;
      }
      res.json(payload);
    } catch (err) {
      next(err);
    }
  }
);

// ── POST /api/auth/reset-password ─────────────────────────────────────────
router.post(
  "/reset-password",
  otpLimiter(15),
  [
    body("email")
      .isEmail()
      .normalizeEmail()
      .withMessage("Email tidak valid")
      .bail()
      .custom((v) => isAllowedCampusEmail(v))
      .withMessage(CAMPUS_EMAIL_ERROR),
    body("otp").notEmpty().withMessage("Kode OTP wajib diisi"),
    body("new_password")
      .isString()
      .isLength({ min: 8 })
      .withMessage("Password baru minimal 8 karakter")
      .bail()
      .custom((v) => Buffer.byteLength(v, "utf8") <= 72)
      .withMessage("Password baru maksimal 72 karakter"),
  ],
  async (req, res, next) => {
    if (!validate(req, res)) return;
    try {
      const { email, otp, new_password } = req.body;
      const invalid = () => res.status(400).json({ error: "Kode OTP tidak valid atau sudah kedaluwarsa" });

      // Ambil OTP aktif terbaru untuk email ini
      let hasAttemptsCol = true;
      let { data: record, error } = await supabase
        .from("password_reset_otps")
        .select("id, user_id, otp_code, attempts")
        .eq("email", email)
        .eq("used", false)
        .gte("expires_at", new Date().toISOString())
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error && isMissingColumn(error, "attempts")) {
        hasAttemptsCol = false;
        ({ data: record, error } = await supabase
          .from("password_reset_otps")
          .select("id, user_id, otp_code")
          .eq("email", email)
          .eq("used", false)
          .gte("expires_at", new Date().toISOString())
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle());
      }
      if (error) throw error;
      if (!record) return invalid();

      // Batasi percobaan tebak OTP per kode (anti brute-force 6 digit)
      if (hasAttemptsCol && (record.attempts || 0) >= OTP_MAX_ATTEMPTS) {
        await supabase.from("password_reset_otps").update({ used: true }).eq("id", record.id);
        return invalid();
      }

      if (!safeEqual(record.otp_code, otpDigest(email, String(otp).trim()))) {
        if (hasAttemptsCol) {
          await supabase
            .from("password_reset_otps")
            .update({ attempts: (record.attempts || 0) + 1 })
            .eq("id", record.id);
        }
        return invalid();
      }

      // Tandai dipakai secara atomik (cegah dipakai dua kali pada request paralel)
      const { data: claimed, error: claimErr } = await supabase
        .from("password_reset_otps")
        .update({ used: true })
        .eq("id", record.id)
        .eq("used", false)
        .select("id");
      if (claimErr) throw claimErr;
      if (!claimed || claimed.length === 0) return invalid();

      const password_hash = await bcrypt.hash(new_password, BCRYPT_ROUNDS);
      const { error: updErr } = await supabase
        .from("users")
        .update({ password_hash, refresh_token: null })
        .eq("id", record.user_id);
      if (updErr) throw updErr;

      res.json({ message: "Password berhasil direset. Silakan login kembali." });
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
