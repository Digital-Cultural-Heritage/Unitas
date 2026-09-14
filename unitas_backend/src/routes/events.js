const express = require("express");
const { body, validationResult } = require("express-validator");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");

const router = express.Router();

// ── GET /api/events ───────────────────────────────────────────────────────
router.get("/", async (req, res, next) => {
  try {
    const { category, page = 1, limit = 20 } = req.query;
    const offset = (Number(page) - 1) * Number(limit);

    let dbQuery = supabase
      .from("events")
      .select(`
        id, title, description, category, event_date, start_time, end_time,
        location, is_online, cover_url, attendee_count, created_at,
        creator:creator_id(id, user_profiles(full_name))
      `, { count: "exact" })
      .gte("event_date", new Date().toISOString().split("T")[0])
      .order("event_date", { ascending: true })
      .range(offset, offset + Number(limit) - 1);

    if (category && category !== "Semua") {
      dbQuery = dbQuery.eq("category", category);
    }

    const { data, count, error } = await dbQuery;
    if (error) throw error;
    res.json({ data, total: count, page: Number(page), limit: Number(limit) });
  } catch (err) {
    next(err);
  }
});

// ── GET /api/events/:id ───────────────────────────────────────────────────
router.get("/:id", async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("events")
      .select(`
        *, creator:creator_id(id, user_profiles(full_name, avatar_url))
      `)
      .eq("id", req.params.id)
      .single();
    if (error || !data) return res.status(404).json({ error: "Acara tidak ditemukan" });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// ── POST /api/events — Buat acara (semua user ber-JWT) ────────────────────
router.post(
  "/",
  requireAuth,
  [
    body("title").notEmpty().withMessage("Judul acara wajib diisi"),
    body("event_date").isDate().withMessage("Tanggal acara tidak valid"),
    body("location").notEmpty().withMessage("Lokasi acara wajib diisi"),
    body("category").notEmpty().withMessage("Kategori acara wajib diisi"),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    try {
      const { title, description, category, event_date, start_time, end_time, location, is_online, cover_url } = req.body;
      const { data, error } = await supabase
        .from("events")
        .insert({
          creator_id: req.user.userId,
          title, description, category, event_date,
          start_time, end_time, location,
          is_online: is_online || false,
          cover_url: cover_url || null,
        })
        .select()
        .single();
      if (error) throw error;
      res.status(201).json(data);
    } catch (err) {
      next(err);
    }
  }
);

// ── POST /api/events/:id/register — Daftar ke acara ──────────────────────
router.post("/:id/register", requireAuth, async (req, res, next) => {
  try {
    const { id: eventId } = req.params;
    const userId = req.user.userId;

    // Cek event ada
    const { data: event } = await supabase.from("events").select("id").eq("id", eventId).single();
    if (!event) return res.status(404).json({ error: "Acara tidak ditemukan" });

    // Cek sudah terdaftar
    const { data: existing } = await supabase
      .from("event_registrations")
      .select("id")
      .eq("event_id", eventId)
      .eq("user_id", userId)
      .single();
    if (existing) return res.status(409).json({ error: "Sudah terdaftar di acara ini" });

    const { data, error } = await supabase
      .from("event_registrations")
      .insert({ event_id: eventId, user_id: userId })
      .select()
      .single();
    if (error) throw error;
    res.status(201).json({ message: "Berhasil mendaftar", registration: data });
  } catch (err) {
    next(err);
  }
});

// ── DELETE /api/events/:id/register — Batal daftar ───────────────────────
router.delete("/:id/register", requireAuth, async (req, res, next) => {
  try {
    const { error } = await supabase
      .from("event_registrations")
      .delete()
      .eq("event_id", req.params.id)
      .eq("user_id", req.user.userId);
    if (error) throw error;
    res.json({ message: "Pendaftaran dibatalkan" });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
