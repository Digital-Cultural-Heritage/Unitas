const express = require("express");
const multer = require("multer");
const sharp = require("sharp");
const crypto = require("crypto");
const { PDFDocument } = require("pdf-lib");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");

const router = express.Router();

const MAX_CV_FINAL_BYTES = 1024 * 1024; // 1 MB

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

// Multer: simpan gambar di memory (bukan disk), cek tipe file
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

// Multer: input PDF CV hingga 4 MB (batas aman payload Vercel) sebelum dikompresi ke <= 1 MB
const uploadPdf = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 4 * 1024 * 1024, files: 1 },
  fileFilter(req, file, cb) {
    const isPdfMime = file.mimetype === "application/pdf";
    const isPdfName = (file.originalname || "").toLowerCase().endsWith(".pdf");
    if (isPdfMime || isPdfName) {
      cb(null, true);
    } else {
      const err = new Error("Format CV harus berupa file PDF.");
      err.status = 400;
      cb(err);
    }
  },
});

function handleMulter(middleware) {
  return (req, res, next) => {
    middleware(req, res, (err) => {
      if (!err) return next();
      if (err.code === "LIMIT_FILE_SIZE") {
        return res.status(400).json({ error: "Ukuran file input terlalu besar." });
      }
      return res.status(err.status || 400).json({ error: err.message || "Gagal memproses file." });
    });
  };
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

async function compressPdfBuffer(inputBuffer) {
  let finalBuffer = inputBuffer;
  try {
    const pdfDoc = await PDFDocument.load(inputBuffer, {
      ignoreEncryption: true,
      updateMetadata: false,
    });
    pdfDoc.setTitle("");
    pdfDoc.setAuthor("");
    pdfDoc.setSubject("");
    pdfDoc.setKeywords([]);
    pdfDoc.setProducer("");
    pdfDoc.setCreator("");

    const savedBytes = await pdfDoc.save({
      useObjectStreams: true,
      addDefaultPage: false,
      objectsPerTick: 50,
    });
    const compressedBuffer = Buffer.from(savedBytes);
    if (compressedBuffer.length < inputBuffer.length) {
      finalBuffer = compressedBuffer;
    }
  } catch (e) {
    // Jika struktur PDF terenkripsi/khusus gagal di-repack, pakai buffer asli bila lolos batas ukuran
    console.warn("[CV Compress] Fallback original PDF:", e.message);
  }
  return finalBuffer;
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

// ── POST /api/upload/cv — Kompres PDF & maksimal 1 MB ─────────────────────
router.post("/cv", requireAuth, handleMulter(uploadPdf.single("file")), async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: "File CV PDF wajib diunggah" });

    const header = req.file.buffer.subarray(0, 5).toString("latin1");
    if (header !== "%PDF-") {
      return res.status(400).json({ error: "File bukan PDF yang valid." });
    }

    const finalBuffer = await compressPdfBuffer(req.file.buffer);
    if (finalBuffer.length > MAX_CV_FINAL_BYTES) {
      const sizeKb = Math.ceil(finalBuffer.length / 1024);
      return res.status(400).json({
        error: `Ukuran PDF setelah kompresi (${sizeKb} KB) masih melebihi batas maksimal 1 MB (1024 KB).`,
      });
    }

    const filePath = `${req.user.userId}/${crypto.randomUUID()}.pdf`;
    const { error: uploadErr } = await supabase.storage
      .from("cvs")
      .upload(filePath, finalBuffer, {
        contentType: "application/pdf",
        upsert: false,
      });
    if (uploadErr) throw uploadErr;

    const { data: urlData } = supabase.storage.from("cvs").getPublicUrl(filePath);
    res.json({
      url: urlData.publicUrl,
      size_bytes: finalBuffer.length,
      original_bytes: req.file.buffer.length,
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
