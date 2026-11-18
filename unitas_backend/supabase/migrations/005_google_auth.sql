-- 005_google_auth.sql
-- Google Sign-In + hardening OTP reset password.
-- Jalankan di Supabase SQL Editor (aman dijalankan berulang).

-- 1. Identitas Google (claim `sub` dari ID token) untuk akun yang login via Google
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS google_sub TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_sub
  ON users(google_sub)
  WHERE google_sub IS NOT NULL;

-- 2. Penghitung percobaan salah OTP (batas 5x per kode, anti brute-force)
ALTER TABLE password_reset_otps
  ADD COLUMN IF NOT EXISTS attempts INTEGER NOT NULL DEFAULT 0;

-- 3. Index untuk pencarian refresh token (logout / rotasi token)
CREATE INDEX IF NOT EXISTS idx_users_refresh_token
  ON users(refresh_token)
  WHERE refresh_token IS NOT NULL;

-- Catatan: kolom users.password_hash tetap NOT NULL. Akun Google diberi penanda
-- '!no-password' (bukan hash bcrypt) sehingga tidak bisa login dengan password
-- sampai user memakai "Lupa password" untuk membuat password.
