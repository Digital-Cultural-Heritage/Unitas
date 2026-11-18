const express = require("express");
const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const { body, validationResult } = require("express-validator");
const supabase = require("../lib/supabase");
const { signAccessToken, signRefreshToken, verifyRefreshToken } = require("../lib/jwt");
const { requireAuth } = require("../middleware/auth");

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

// ── POST /api/auth/change-password ────────────────────────────────────────
router.post(
  "/change-password",
  requireAuth,
  [
    body("current_password").notEmpty().withMessage("Password saat ini wajib diisi"),
    body("new_password").isLength({ min: 8 }).withMessage("Password baru minimal 8 karakter"),
  ],
  async (req, res, next) => {
    if (!validate(req, res)) return;
    try {
      const { current_password, new_password } = req.body;
      const { data: user, error } = await supabase
        .from("users")
        .select("id, password_hash")
        .eq("id", req.user.userId)
        .single();
      if (error || !user) return res.status(404).json({ error: "User tidak ditemukan" });

      const match = await bcrypt.compare(current_password, user.password_hash);
      if (!match) return res.status(401).json({ error: "Password saat ini salah" });

      const password_hash = await bcrypt.hash(new_password, 12);
      const { error: updErr } = await supabase
        .from("users")
        .update({ password_hash })
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
  [body("email").isEmail().normalizeEmail().withMessage("Email tidak valid")],
  async (req, res, next) => {
    if (!validate(req, res)) return;
    try {
      const { email } = req.body;
      const { data: user } = await supabase
        .from("users")
        .select("id, email")
        .eq("email", email)
        .single();

      // Always return generic success to avoid leaking registered emails
      if (!user) {
        return res.json({ message: "Jika email terdaftar, kode OTP telah dikirim" });
      }

      const otpCode = String(crypto.randomInt(100000, 1000000));
      const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();

      await supabase
        .from("password_reset_otps")
        .insert({
          user_id: user.id,
          email: user.email,
          otp_code: otpCode,
          expires_at: expiresAt,
        });

      // Optional email dispatch via Resend if configured
      if (process.env.RESEND_API_KEY) {
        await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from: process.env.EMAIL_FROM || "Unitas <noreply@unitas.app>",
            to: [user.email],
            subject: "Kode Reset Password Unitas",
            html: `<p>Kode OTP reset password kamu adalah: <strong>${otpCode}</strong>. Berlaku selama 15 menit.</p>`,
          }),
        }).catch((e) => console.error("Resend email error:", e.message));
      } else {
        console.log(`[Unitas OTP] ${user.email}: ${otpCode}`);
      }

      const payload = { message: "Jika email terdaftar, kode OTP telah dikirim" };
      if (process.env.NODE_ENV !== "production" && !process.env.RESEND_API_KEY) {
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
  [
    body("email").isEmail().normalizeEmail().withMessage("Email tidak valid"),
    body("otp").notEmpty().withMessage("Kode OTP wajib diisi"),
    body("new_password").isLength({ min: 8 }).withMessage("Password baru minimal 8 karakter"),
  ],
  async (req, res, next) => {
    if (!validate(req, res)) return;
    try {
      const { email, otp, new_password } = req.body;
      const nowIso = new Date().toISOString();

      const { data: record } = await supabase
        .from("password_reset_otps")
        .select("id, user_id, otp_code, expires_at")
        .eq("email", email)
        .eq("otp_code", String(otp).trim())
        .eq("used", false)
        .gte("expires_at", nowIso)
        .order("created_at", { ascending: false })
        .limit(1)
        .single();

      if (!record) {
        return res.status(400).json({ error: "Kode OTP tidak valid atau sudah kedaluwarsa" });
      }

      const password_hash = await bcrypt.hash(new_password, 12);
      const { error: updErr } = await supabase
        .from("users")
        .update({ password_hash, refresh_token: null })
        .eq("id", record.user_id);
      if (updErr) throw updErr;

      await supabase
        .from("password_reset_otps")
        .update({ used: true })
        .eq("id", record.id);

      res.json({ message: "Password berhasil direset. Silakan login kembali." });
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
