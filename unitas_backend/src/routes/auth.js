const express = require("express");
const bcrypt = require("bcryptjs");
const { body, validationResult } = require("express-validator");
const supabase = require("../lib/supabase");
const { signAccessToken, signRefreshToken, verifyRefreshToken } = require("../lib/jwt");

const router = express.Router();

// ── Helpers ──────────────────────────────────────────────────────────────
function validate(req, res) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    res.status(400).json({ errors: errors.array() });
    return false;
  }
  return true;
}

// ── POST /api/auth/register ───────────────────────────────────────────────
router.post(
  "/register",
  [
    body("email").isEmail().normalizeEmail().withMessage("Email tidak valid"),
    body("password").isLength({ min: 8 }).withMessage("Password minimal 8 karakter"),
    body("full_name").notEmpty().withMessage("Nama lengkap wajib diisi"),
    body("prodi").notEmpty().withMessage("Program studi wajib diisi"),
    body("angkatan").notEmpty().withMessage("Angkatan wajib diisi"),
  ],
  async (req, res, next) => {
    if (!validate(req, res)) return;
    try {
      const { email, password, full_name, prodi, angkatan, kota } = req.body;

      // Cek email sudah terdaftar
      const { data: existing } = await supabase
        .from("users")
        .select("id")
        .eq("email", email)
        .single();
      if (existing) return res.status(409).json({ error: "Email sudah terdaftar" });

      // Hash password
      const password_hash = await bcrypt.hash(password, 12);

      // Buat user
      const { data: user, error: userErr } = await supabase
        .from("users")
        .insert({ email, password_hash })
        .select("id, email, role")
        .single();
      if (userErr) throw userErr;

      // Buat profil
      const { error: profileErr } = await supabase
        .from("user_profiles")
        .insert({ user_id: user.id, full_name, prodi, angkatan, kota: kota || null });
      if (profileErr) throw profileErr;

      // Generate tokens
      const tokenPayload = { userId: user.id, email: user.email, role: user.role };
      const accessToken  = signAccessToken(tokenPayload);
      const refreshToken = signRefreshToken(tokenPayload);

      // Simpan refresh token
      await supabase.from("users").update({ refresh_token: refreshToken }).eq("id", user.id);

      res.status(201).json({
        message: "Registrasi berhasil",
        access_token: accessToken,
        refresh_token: refreshToken,
        user: { id: user.id, email: user.email, role: user.role, full_name },
      });
    } catch (err) {
      next(err);
    }
  }
);

// ── POST /api/auth/login ──────────────────────────────────────────────────
router.post(
  "/login",
  [
    body("email").isEmail().normalizeEmail(),
    body("password").notEmpty(),
  ],
  async (req, res, next) => {
    if (!validate(req, res)) return;
    try {
      const { email, password } = req.body;

      // Cari user beserta profil
      const { data: user } = await supabase
        .from("users")
        .select("id, email, password_hash, role, user_profiles(full_name, avatar_url)")
        .eq("email", email)
        .single();

      if (!user) return res.status(401).json({ error: "Email atau password salah" });

      const match = await bcrypt.compare(password, user.password_hash);
      if (!match) return res.status(401).json({ error: "Email atau password salah" });

      // Generate tokens
      const tokenPayload = { userId: user.id, email: user.email, role: user.role };
      const accessToken  = signAccessToken(tokenPayload);
      const refreshToken = signRefreshToken(tokenPayload);

      await supabase.from("users").update({ refresh_token: refreshToken }).eq("id", user.id);

      const profile = user.user_profiles?.[0] || {};
      res.json({
        access_token: accessToken,
        refresh_token: refreshToken,
        user: {
          id: user.id,
          email: user.email,
          role: user.role,
          full_name: profile.full_name,
          avatar_url: profile.avatar_url,
        },
      });
    } catch (err) {
      next(err);
    }
  }
);

// ── POST /api/auth/refresh ────────────────────────────────────────────────
router.post("/refresh", async (req, res, next) => {
  try {
    const { refresh_token } = req.body;
    if (!refresh_token) return res.status(400).json({ error: "Refresh token wajib diisi" });

    let decoded;
    try {
      decoded = verifyRefreshToken(refresh_token);
    } catch {
      return res.status(401).json({ error: "Refresh token tidak valid atau sudah kedaluwarsa" });
    }

    // Validasi token di DB
    const { data: user } = await supabase
      .from("users")
      .select("id, email, role, refresh_token")
      .eq("id", decoded.userId)
      .single();

    if (!user || user.refresh_token !== refresh_token) {
      return res.status(401).json({ error: "Refresh token tidak cocok" });
    }

    const tokenPayload = { userId: user.id, email: user.email, role: user.role };
    const newAccessToken  = signAccessToken(tokenPayload);
    const newRefreshToken = signRefreshToken(tokenPayload);

    await supabase.from("users").update({ refresh_token: newRefreshToken }).eq("id", user.id);

    res.json({ access_token: newAccessToken, refresh_token: newRefreshToken });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/auth/logout ─────────────────────────────────────────────────
router.post("/logout", async (req, res, next) => {
  try {
    const { refresh_token } = req.body;
    if (refresh_token) {
      await supabase
        .from("users")
        .update({ refresh_token: null })
        .eq("refresh_token", refresh_token);
    }
    res.json({ message: "Logout berhasil" });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
