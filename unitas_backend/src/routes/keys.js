/**
 * routes/keys.js
 * Endpoint untuk manajemen public key E2EE (X3DH / Double Ratchet)
 * Backend HANYA menyimpan public key — private key tidak pernah dikirim ke sini.
 */

const express = require("express");
const { body, param, validationResult } = require("express-validator");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");
const { uuidParam } = require("../lib/validate");

const router = express.Router();

// ── POST /api/keys/register ───────────────────────────────────────────────
// Upload/update public key bundle milik user yang sedang login.
// Dipanggil sekali saat pertama kali login atau saat prekey di-rotate.
router.post(
  "/register",
  requireAuth,
  [
    body("identity_public_key")
      .isString()
      .notEmpty()
      .withMessage("identity_public_key wajib diisi"),
    body("signing_public_key")
      .isString()
      .notEmpty()
      .withMessage("signing_public_key wajib diisi"),
    body("signed_prekey_public")
      .isString()
      .notEmpty()
      .withMessage("signed_prekey_public wajib diisi"),
    body("signed_prekey_signature")
      .isString()
      .notEmpty()
      .withMessage("signed_prekey_signature wajib diisi"),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    try {
      const userId = req.user.userId;
      const {
        identity_public_key,
        signing_public_key,
        signed_prekey_public,
        signed_prekey_signature,
      } = req.body;

      // Upsert: kalau sudah ada, update; kalau belum, insert
      const { data, error } = await supabase
        .from("user_keys")
        .upsert(
          {
            user_id: userId,
            identity_public_key,
            signing_public_key,
            signed_prekey_public,
            signed_prekey_signature,
          },
          { onConflict: "user_id" }
        )
        .select("user_id, updated_at")
        .single();

      if (error) throw error;

      res.status(200).json({ success: true, user_id: data.user_id, updated_at: data.updated_at });
    } catch (err) {
      next(err);
    }
  }
);

// ── GET /api/keys/:userId ─────────────────────────────────────────────────
// Ambil public key bundle milik user lain untuk memulai sesi E2EE.
// Hanya mengembalikan public key — tidak ada secret.
router.get("/:userId", requireAuth, [param("userId").isUUID()], async (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ error: "userId tidak valid" });
  }

  try {
    const targetId = req.params.userId;

    const { data, error } = await supabase
      .from("user_keys")
      .select("user_id, identity_public_key, signing_public_key, signed_prekey_public, signed_prekey_signature, updated_at")
      .eq("user_id", targetId)
      .single();

    if (error) {
      if (error.code === "PGRST116") {
        // Row not found
        return res.status(404).json({ error: "Public key tidak ditemukan untuk user ini. Minta user tersebut untuk membuka aplikasi terlebih dahulu." });
      }
      throw error;
    }

    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

