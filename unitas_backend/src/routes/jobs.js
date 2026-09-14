const express = require("express");
const { body, validationResult } = require("express-validator");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");

const router = express.Router();

// ── GET /api/jobs/saved — Harus sebelum /:id ─────────────────────────────
router.get("/saved", requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("saved_jobs")
      .select(`
        id, saved_at,
        job:job_id(
          id, title, company, company_logo, location, job_type,
          salary_min, salary_max, tags,
          poster:poster_id(id, user_profiles(full_name))
        )
      `)
      .eq("user_id", req.user.userId)
      .order("saved_at", { ascending: false });
    if (error) throw error;
    res.json({ data: data.map((s) => s.job) });
  } catch (err) {
    next(err);
  }
});

// ── GET /api/jobs ─────────────────────────────────────────────────────────
router.get("/", async (req, res, next) => {
  try {
    const { q = "", type, is_remote, page = 1, limit = 20 } = req.query;
    const offset = (Number(page) - 1) * Number(limit);

    let dbQuery = supabase
      .from("jobs")
      .select(`
        id, title, company, company_logo, location, job_type,
        salary_min, salary_max, tags, created_at,
        poster:poster_id(id, user_profiles(full_name, prodi, angkatan))
      `, { count: "exact" })
      .eq("is_active", true)
      .order("created_at", { ascending: false })
      .range(offset, offset + Number(limit) - 1);

    if (q) dbQuery = dbQuery.or(`title.ilike.%${q}%,company.ilike.%${q}%`);
    if (type) dbQuery = dbQuery.eq("job_type", type);
    if (is_remote === "true") dbQuery = dbQuery.ilike("location", "%Remote%");

    const { data, count, error } = await dbQuery;
    if (error) throw error;
    res.json({ data, total: count, page: Number(page), limit: Number(limit) });
  } catch (err) {
    next(err);
  }
});

// ── GET /api/jobs/:id ─────────────────────────────────────────────────────
router.get("/:id", async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("jobs")
      .select(`*, poster:poster_id(id, user_profiles(full_name, avatar_url, prodi, angkatan))`)
      .eq("id", req.params.id)
      .single();
    if (error || !data) return res.status(404).json({ error: "Lowongan tidak ditemukan" });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// ── POST /api/jobs — Post lowongan baru ───────────────────────────────────
router.post(
  "/",
  requireAuth,
  [
    body("title").notEmpty().withMessage("Judul posisi wajib diisi"),
    body("company").notEmpty().withMessage("Nama perusahaan wajib diisi"),
    body("location").notEmpty().withMessage("Lokasi wajib diisi"),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    try {
      const { title, company, company_logo, location, job_type, salary_min, salary_max, tags, description } = req.body;
      const { data, error } = await supabase
        .from("jobs")
        .insert({
          poster_id: req.user.userId,
          title, company, company_logo, location,
          job_type: job_type || "Full-time",
          salary_min: salary_min || null,
          salary_max: salary_max || null,
          tags: tags || [],
          description: description || null,
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

// ── POST /api/jobs/:id/save — Toggle simpan ───────────────────────────────
router.post("/:id/save", requireAuth, async (req, res, next) => {
  try {
    const jobId = req.params.id;
    const userId = req.user.userId;

    const { data: existing } = await supabase
      .from("saved_jobs")
      .select("id")
      .eq("job_id", jobId)
      .eq("user_id", userId)
      .single();

    if (existing) {
      await supabase.from("saved_jobs").delete().eq("id", existing.id);
      res.json({ saved: false });
    } else {
      await supabase.from("saved_jobs").insert({ job_id: jobId, user_id: userId });
      res.json({ saved: true });
    }
  } catch (err) {
    next(err);
  }
});

module.exports = router;
