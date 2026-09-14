const express = require("express");
const multer = require("multer");
const sharp = require("sharp");
const { v4: uuidv4 } = require("uuid");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");

const router = express.Router();

// Multer: simpan di memory (bukan disk), cek tipe file
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }, // max 10 MB input
  fileFilter(req, file, cb) {
    const allowed = ["image/jpeg", "image/png", "image/webp", "image/heic", "image/gif"];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error("Format file tidak didukung. Gunakan JPG, PNG, atau WebP."));
    }
  },
});

// ── POST /api/upload/avatar ───────────────────────────────────────────────
router.post("/avatar", requireAuth, upload.single("file"), async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: "File gambar wajib diunggah" });

    // Konversi ke WebP: resize max 400x400, quality 85, strip metadata
    const webpBuffer = await sharp(req.file.buffer)
      .resize(400, 400, { fit: "cover", position: "center" })
      .webp({ quality: 85 })
      .withMetadata(false)
      .toBuffer();

    const fileName = `${req.user.userId}.webp`;
    const filePath = fileName;

    const { error: uploadErr } = await supabase.storage
      .from("avatars")
      .upload(filePath, webpBuffer, {
        contentType: "image/webp",
        upsert: true, // overwrite existing avatar
      });
    if (uploadErr) throw uploadErr;

    const { data: urlData } = supabase.storage.from("avatars").getPublicUrl(filePath);
    const publicUrl = urlData.publicUrl;

    // Update avatar_url di profil
    await supabase
      .from("user_profiles")
      .update({ avatar_url: publicUrl })
      .eq("user_id", req.user.userId);

    res.json({ url: publicUrl });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/upload/post ─────────────────────────────────────────────────
router.post("/post", requireAuth, upload.single("file"), async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: "File gambar wajib diunggah" });

    // Konversi ke WebP: resize max lebar 1200px, quality 80, strip metadata
    const webpBuffer = await sharp(req.file.buffer)
      .resize({ width: 1200, withoutEnlargement: true })
      .webp({ quality: 80 })
      .withMetadata(false)
      .toBuffer();

    const fileName = `${uuidv4()}.webp`;

    const { error: uploadErr } = await supabase.storage
      .from("post-images")
      .upload(fileName, webpBuffer, {
        contentType: "image/webp",
        upsert: false,
      });
    if (uploadErr) throw uploadErr;

    const { data: urlData } = supabase.storage.from("post-images").getPublicUrl(fileName);
    res.json({ url: urlData.publicUrl });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
