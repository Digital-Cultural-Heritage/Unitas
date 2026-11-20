-- Migration: 008_add_e2ee_keys.sql
-- Tambah tabel user_keys dan kolom E2EE pada tabel messages
-- Prinsip: backend TIDAK menyimpan private key, hanya menerima/meneruskan ciphertext

-- ── Tabel user_keys ───────────────────────────────────────────────────────
-- Menyimpan HANYA public key milik setiap user.
-- Private key TIDAK PERNAH dikirim ke server — disimpan di device via flutter_secure_storage.
CREATE TABLE IF NOT EXISTS user_keys (
  user_id              UUID        PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  identity_public_key  TEXT        NOT NULL,  -- X25519 public key (base64)
  signing_public_key   TEXT        NOT NULL,  -- Ed25519 public key (base64) untuk verifikasi signature prekey
  signed_prekey_public TEXT        NOT NULL,  -- X25519 prekey public (base64), di-rotate berkala
  signed_prekey_signature TEXT     NOT NULL,  -- Signature Ed25519 atas signed_prekey_public (base64)
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index untuk lookup cepat
CREATE INDEX IF NOT EXISTS idx_user_keys_user_id ON user_keys(user_id);

-- Trigger update updated_at otomatis
CREATE OR REPLACE FUNCTION update_user_keys_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_user_keys_updated_at ON user_keys;
CREATE TRIGGER trg_user_keys_updated_at
  BEFORE UPDATE ON user_keys
  FOR EACH ROW EXECUTE FUNCTION update_user_keys_updated_at();

-- ── Modifikasi tabel messages ─────────────────────────────────────────────
-- Tambah kolom E2EE. Kolom `content` dijadikan nullable untuk backward compatibility
-- (pesan lama tetap terbaca, pesan baru menggunakan ciphertext).
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS ciphertext              TEXT,       -- ciphertext XChaCha20-Poly1305, base64
  ADD COLUMN IF NOT EXISTS nonce                   TEXT,       -- nonce 24 byte, base64
  ADD COLUMN IF NOT EXISTS sender_ratchet_public_key TEXT,    -- DH ratchet public key pengirim, base64
  ADD COLUMN IF NOT EXISTS message_number          INTEGER DEFAULT 0,     -- nomor urut pesan dalam ratchet chain
  ADD COLUMN IF NOT EXISTS previous_chain_length   INTEGER DEFAULT 0,     -- panjang chain sebelum DH ratchet
  ADD COLUMN IF NOT EXISTS ephemeral_public_key    TEXT;      -- ephemeral key X3DH (hanya pesan pertama sesi)

-- Jadikan content nullable (agar pesan E2EE bisa content = NULL)
ALTER TABLE messages ALTER COLUMN content DROP NOT NULL;

-- ── RLS (Row Level Security) untuk user_keys ──────────────────────────────
-- Jika project Supabase menggunakan RLS, tambahkan policy berikut.
-- Sesuaikan bila menggunakan service_role key (bypass RLS otomatis).
-- ALTER TABLE user_keys ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "users can read all public keys" ON user_keys FOR SELECT USING (true);
-- CREATE POLICY "users can upsert own keys" ON user_keys FOR ALL USING (auth.uid() = user_id);

