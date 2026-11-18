const express = require("express");
const multer = require("multer");
const sharp = require("sharp");
const crypto = require("crypto");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");

const router = express.Router();

const ALLOWED_MIMES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
  "image/gif",
]);

const ALLOWED_SHARP_FORMATS = new Set(["jpeg", "png", "webp", "gif", "heif"]);
const SHARP_OPTS = { limitInputPixels: 25_000_000 }; // guard against pixel-bomb DoS

// Multer: simpan di memory (bukan disk), cek tipe file
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024, files: 1 }, // max 10 MB input, 1 file
  fileFilter(req, file, cb) {
    if (ALLOWED_MIMES.has(file.mimetype)) {
      cb(null, true);
    } else {
      const err = new Error("Format file tidak didukung. Gunakan JPG, PNG, atau WebP.");
      err.status = 400;
      cb(err);
    }
  },
});

function handleUpload(req, res, next) {
  upload.single("file")(req, res, (err) => {
    if (!err) return next();
    if (err instanceof multer.MulterError) {
      if (err.code === "LIMIT_FILE_SIZE") {
        return res.status(413).json({ error: "Ukuran file maksimal 10 MB" });
      }
      return res.status(400).json({ error: `Upload gagal: ${err.message}` });
    }
    return res.status(err.status || 400).json({ error: err.message });
  });
}

async function sanitizeImage(buffer, transformFn) {
  let meta;
  try {
    meta = await sharp(buffer, SHARP_OPTS).metadata();
  } catch (_) {
    const err = new Error("File gambar tidak valid atau rusak");
    err.status = 400;
    throw err;
  }
  if (!meta || !ALLOWED_SHARP_FORMATS.has(meta.format)) {
    const err = new Error("Format gambar tidak didukung. Gunakan JPG, PNG, atau WebP.");
    err.status = 400;
    throw err;
  }
  try {
    // .rotate() normalizes EXIF orientation; omitting .withMetadata() strips EXIF/GPS tags.
    return await transformFn(sharp(buffer, SHARP_OPTS).rotate()).toBuffer();
  } catch (_) {
    const err = new Error("Gagal memproses gambar");
    err.status = 400;
    throw err;
  }
}

// ── POST /api/upload/avatar ───────────────────────────────────────────────
router.post("/avatar", requireAuth, handleUpload, async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: "File gambar wajib diunggah" });

    // Konversi ke WebP: resize max 400x400, quality 85, strip metadata
    const webpBuffer = await sanitizeImage(req.file.buffer, (img) =>
      img.resize(400, 400, { fit: "cover", position: "center" }).webp({ quality: 85 })
    );

    const filePath = `${req.user.userId}.webp`;

    const { error: uploadErr } = await supabase.storage
      .from("avatars")
      .upload(filePath, webpBuffer, {
        contentType: "image/webp",
        upsert: true, // overwrite existing avatar
      });
    if (uploadErr) throw uploadErr;

    const { data: urlData } = supabase.storage.from("avatars").getPublicUrl(filePath);
    // Append version query so CDN/client caches refresh when the avatar is overwritten.
    const publicUrl = `${urlData.publicUrl}?v=${Date.now()}`;

    // Update avatar_url di profil
    const { error: dbErr } = await supabase
      .from("user_profiles")
      .update({ avatar_url: publicUrl })
      .eq("user_id", req.user.userId);
    if (dbErr) throw dbErr;

    res.json({ url: publicUrl });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/upload/post ─────────────────────────────────────────────────
router.post("/post", requireAuth, handleUpload, async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: "File gambar wajib diunggah" });

    // Konversi ke WebP: resize max lebar 1200px, quality 80, strip metadata
    const webpBuffer = await sanitizeImage(req.file.buffer, (img) =>
      img.resize({ width: 1200, withoutEnlargement: true }).webp({ quality: 80 })
    );

    const fileName = `${crypto.randomUUID()}.webp`;

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
