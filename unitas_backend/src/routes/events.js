const express = require("express");
const { body, validationResult } = require("express-validator");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");
const {
  uuidParam,
  parsePagination,
  isHttpUrl,
  isUniqueViolation,
  isFkViolation,
} = require("../lib/validate");

const router = express.Router();

router.param("id", uuidParam);

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function isValidDate(v) {
  if (typeof v !== "string" || !DATE_RE.test(v)) return false;
  const d = new Date(`${v}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().startsWith(v);
}

function textOk(v, max) {
  return typeof v === "string" && v.trim().length > 0 && v.length <= max;
}

/**
 * Validate and normalise the event fields found in `src`.
 * `requireAll` = true for create. Returns { errors: [...], values: {...} }.
 */
function buildEventFields(src, requireAll) {
  const errors = [];
  const values = {};
  const has = (k) => src[k] !== undefined;

  const reqText = (key, max, msg) => {
    if (has(key)) {
      if (!textOk(src[key], max)) errors.push({ msg, path: key });
      else values[key] = src[key].trim();
    } else if (requireAll) {
      errors.push({ msg, path: key });
    }
  };
  reqText("title", 200, "Judul acara wajib diisi (maks 200 karakter)");
  reqText("location", 300, "Lokasi acara wajib diisi (maks 300 karakter)");
  reqText("category", 50, "Kategori acara wajib diisi");

  if (has("event_date")) {
    if (!isValidDate(src.event_date)) errors.push({ msg: "Tanggal acara tidak valid", path: "event_date" });
    else values.event_date = src.event_date;
  } else if (requireAll) {
    errors.push({ msg: "Tanggal acara tidak valid", path: "event_date" });
  }

  if (has("description")) {
    if (src.description === null) values.description = null;
    else if (typeof src.description === "string" && src.description.length <= 5000) values.description = src.description;
    else errors.push({ msg: "Deskripsi tidak valid", path: "description" });
  }
  for (const key of ["start_time", "end_time"]) {
    if (has(key)) {
      if (src[key] === null || src[key] === "") values[key] = null;
      else if (typeof src[key] === "string" && src[key].length <= 20) values[key] = src[key];
      else errors.push({ msg: `${key} tidak valid`, path: key });
    }
  }
  if (has("is_online")) {
    if (typeof src.is_online === "boolean") values.is_online = src.is_online;
    else if (src.is_online === "true" || src.is_online === "false") values.is_online = src.is_online === "true";
    else errors.push({ msg: "is_online tidak valid", path: "is_online" });
  }
  if (has("cover_url")) {
    if (src.cover_url === null || src.cover_url === "") values.cover_url = null;
    else if (isHttpUrl(src.cover_url)) values.cover_url = src.cover_url;
    else errors.push({ msg: "cover_url tidak valid", path: "cover_url" });
  }
  return { errors, values };
}

// -- GET /api/events -------------------------------------------------------
router.get("/", async (req, res, next) => {
  try {
    const { category } = req.query;
    const { page, limit, offset, to } = parsePagination(req.query);

    let dbQuery = supabase
      .from("events")
      .select(`
        id, title, description, category, event_date, start_time, end_time,
        location, is_online, cover_url, attendee_count, created_at,
        creator:creator_id(id, user_profiles(full_name))
      `, { count: "exact" })
      .gte("event_date", new Date().toISOString().split("T")[0])
      .order("event_date", { ascending: true })
      .order("id", { ascending: true }) // stable pagination
      .range(offset, to);

    if (typeof category === "string" && category && category !== "Semua") {
      dbQuery = dbQuery.eq("category", category);
    }

    const { data, count, error } = await dbQuery;
    if (error) throw error;
    res.json({ data, total: count, page, limit });
  } catch (err) {
    next(err);
  }
});

// -- GET /api/events/my-events/all -------------------------------------------
// (defined before "/:id" style routes for clarity; path has 2 segments so no clash)
router.get("/my-events/all", requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("events")
      .select(`
        id, title, description, category, event_date, start_time, end_time,
        location, is_online, cover_url, attendee_count, created_at
      `)
      .eq("creator_id", req.user.userId)
      .order("event_date", { ascending: false })
      .limit(200);

    if (error) throw error;
    res.json({ data });
  } catch (err) {
    next(err);
  }
});

// -- GET /api/events/:id ---------------------------------------------------
router.get("/:id", async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("events")
      .select(`
        *, creator:creator_id(id, user_profiles(full_name, avatar_url))
      `)
      .eq("id", req.params.id)
      .maybeSingle();
    if (error) throw error;
    if (!data) return res.status(404).json({ error: "Acara tidak ditemukan" });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// -- POST /api/events - Buat acara (semua user ber-JWT) --------------------
router.post("/", requireAuth, async (req, res, next) => {
  try {
    const { errors, values } = buildEventFields(req.body || {}, true);
    if (errors.length) return res.status(400).json({ errors });

    const { data, error } = await supabase
      .from("events")
      .insert({
        creator_id: req.user.userId,
        ...values,
        is_online: values.is_online || false,
        cover_url: values.cover_url || null,
      })
      .select()
      .single();
    if (error) throw error;
    res.status(201).json(data);
  } catch (err) {
    next(err);
  }
});

// -- POST /api/events/:id/register - Daftar ke acara ----------------------
router.post("/:id/register", requireAuth, async (req, res, next) => {
  try {
    const { id: eventId } = req.params;
    const userId = req.user.userId;
    const body = req.body || {};

    const attendee_name = typeof body.attendee_name === "string" ? body.attendee_name.trim() : null;
    const attendee_email = typeof body.attendee_email === "string" ? body.attendee_email.trim() : null;
    const attendee_phone = typeof body.attendee_phone === "string" ? body.attendee_phone.trim() : null;
    const notes = typeof body.notes === "string" ? body.notes.trim() : null;

    if (attendee_email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(attendee_email)) {
      return res.status(400).json({ error: "Format email tidak valid" });
    }

    // Single INSERT; UNIQUE(event_id, user_id) makes this race-free and the
    // attendee_count trigger keeps the counter exact.
    const { data, error } = await supabase
      .from("event_registrations")
      .insert({
        event_id: eventId,
        user_id: userId,
        attendee_name: attendee_name || null,
        attendee_email: attendee_email || null,
        attendee_phone: attendee_phone || null,
        notes: notes || null,
      })
      .select()
      .single();
    if (error) {
      if (isUniqueViolation(error)) return res.status(409).json({ error: "Sudah terdaftar di acara ini" });
      if (isFkViolation(error)) return res.status(404).json({ error: "Acara tidak ditemukan" });
      throw error;
    }
    res.status(201).json({ message: "Berhasil mendaftar", registration: data });
  } catch (err) {
    next(err);
  }
});

// -- DELETE /api/events/:id/register - Batal daftar -----------------------
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

// -- GET /api/events/:id/attendees -------------------------------------------
router.get("/:id/attendees", requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("event_registrations")
      .select(`
        id, registered_at, attendee_name, attendee_email, attendee_phone, notes,
        user:user_id(id, user_profiles(full_name, initials, avatar_url, prodi, angkatan))
      `)
      .eq("event_id", req.params.id)
      .order("registered_at", { ascending: false })
      .limit(500);

    if (error) throw error;
    res.json({ data });
  } catch (err) {
    next(err);
  }
});

// Distinguish 404 vs 403 after an owner-scoped write matched no rows.
async function eventMissingOrForbidden(eventId, res) {
  const { data: ev } = await supabase.from("events").select("id").eq("id", eventId).maybeSingle();
  if (!ev) return res.status(404).json({ error: "Acara tidak ditemukan" });
  return res.status(403).json({ error: "Tidak diizinkan" });
}

// -- PUT /api/events/:id -----------------------------------------------------
router.put("/:id", requireAuth, async (req, res, next) => {
  try {
    const { errors, values } = buildEventFields(req.body || {}, false);
    if (errors.length) return res.status(400).json({ errors });
    if (Object.keys(values).length === 0) {
      return res.status(400).json({ error: "Tidak ada data yang diubah" });
    }

    const { data, error } = await supabase
      .from("events")
      .update(values)
      .eq("id", req.params.id)
      .eq("creator_id", req.user.userId)
      .select()
      .maybeSingle();
    if (error) throw error;
    if (!data) return await eventMissingOrForbidden(req.params.id, res);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// -- DELETE /api/events/:id --------------------------------------------------
router.delete("/:id", requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("events")
      .delete()
      .eq("id", req.params.id)
      .eq("creator_id", req.user.userId)
      .select("id");
    if (error) throw error;
    if (!data || data.length === 0) return await eventMissingOrForbidden(req.params.id, res);
    res.json({ message: "Acara dihapus" });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
