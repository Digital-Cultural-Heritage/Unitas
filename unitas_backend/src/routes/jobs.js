const express = require("express");
const validator = require("validator");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");
const {
  uuidParam,
  parsePagination,
  sanitizeSearch,
  isHttpUrl,
  isUniqueViolation,
  isFkViolation,
} = require("../lib/validate");

const router = express.Router();

router.param("id", uuidParam);

const MAX_SALARY = 2_000_000_000;
const JOB_COLS =
  "id, poster_id, title, company, company_logo, location, job_type, salary_min, salary_max, tags, description, apply_url, contact_email, is_active, created_at, updated_at";

function parseSalary(v) {
  if (v === null || v === undefined || v === "") return { ok: true, value: null };
  const n = typeof v === "number" ? v : Number(String(v).trim());
  if (!Number.isInteger(n) || n < 0 || n > MAX_SALARY) return { ok: false };
  return { ok: true, value: n };
}

/**
 * Validate and normalise job payload fields.
 * `requireAll` = true for create. Returns { errors, values }.
 */
function buildJobFields(src, requireAll) {
  const errors = [];
  const values = {};
  const has = (k) => src[k] !== undefined;

  const reqText = (key, max, msg) => {
    if (has(key)) {
      if (typeof src[key] !== "string" || !src[key].trim() || src[key].trim().length > max) {
        errors.push({ msg, path: key });
      } else {
        values[key] = src[key].trim();
      }
    } else if (requireAll) {
      errors.push({ msg, path: key });
    }
  };
  reqText("title", 200, "Judul posisi wajib diisi (maks 200 karakter)");
  reqText("company", 200, "Nama perusahaan wajib diisi (maks 200 karakter)");
  reqText("location", 200, "Lokasi wajib diisi (maks 200 karakter)");

  if (has("job_type")) {
    if (src.job_type === null || src.job_type === "") {
      values.job_type = "Full-time";
    } else if (typeof src.job_type === "string" && src.job_type.trim().length <= 50) {
      values.job_type = src.job_type.trim();
    } else {
      errors.push({ msg: "Tipe pekerjaan tidak valid", path: "job_type" });
    }
  }

  if (has("description")) {
    if (src.description === null || src.description === "") values.description = null;
    else if (typeof src.description === "string" && src.description.length <= 10000) values.description = src.description;
    else errors.push({ msg: "Deskripsi terlalu panjang (maks 10000 karakter)", path: "description" });
  }

  for (const key of ["company_logo", "apply_url"]) {
    if (has(key)) {
      const raw = src[key];
      if (raw === null || raw === "") values[key] = null;
      else if (typeof raw === "string" && isHttpUrl(raw.trim())) values[key] = raw.trim();
      else errors.push({ msg: `${key} harus berupa URL http(s) yang valid`, path: key });
    }
  }

  if (has("contact_email")) {
    const raw = src.contact_email;
    if (raw === null || raw === "") values.contact_email = null;
    else if (typeof raw === "string" && raw.trim().length <= 254 && validator.isEmail(raw.trim())) {
      values.contact_email = raw.trim();
    } else {
      errors.push({ msg: "Email kontak tidak valid", path: "contact_email" });
    }
  }

  for (const key of ["salary_min", "salary_max"]) {
    if (has(key)) {
      const parsed = parseSalary(src[key]);
      if (!parsed.ok) errors.push({ msg: `${key} harus berupa bilangan bulat non-negatif`, path: key });
      else values[key] = parsed.value;
    }
  }
  if (
    values.salary_min !== undefined &&
    values.salary_min !== null &&
    values.salary_max !== undefined &&
    values.salary_max !== null &&
    values.salary_max < values.salary_min
  ) {
    errors.push({ msg: "Gaji maksimal tidak boleh lebih kecil dari gaji minimal", path: "salary_max" });
  }

  if (has("tags")) {
    if (src.tags === null) {
      values.tags = [];
    } else if (Array.isArray(src.tags) && src.tags.length <= 20) {
      const cleaned = src.tags
        .filter((t) => typeof t === "string")
        .map((t) => t.trim())
        .filter((t) => t.length > 0 && t.length <= 40);
      if (cleaned.length !== src.tags.filter((t) => typeof t === "string" && t.trim()).length ||
          src.tags.some((t) => typeof t !== "string")) {
        errors.push({ msg: "Format tags tidak valid", path: "tags" });
      } else {
        values.tags = cleaned;
      }
    } else {
      errors.push({ msg: "tags harus berupa array maksimal 20 item", path: "tags" });
    }
  }

  if (!requireAll && has("is_active")) {
    if (typeof src.is_active === "boolean") values.is_active = src.is_active;
    else errors.push({ msg: "is_active harus berupa boolean", path: "is_active" });
  }

  return { errors, values };
}

// Distinguish 404 vs 403 after an owner-scoped write matched no rows.
async function jobMissingOrForbidden(jobId, res) {
  const { data: job } = await supabase.from("jobs").select("id").eq("id", jobId).maybeSingle();
  if (!job) return res.status(404).json({ error: "Lowongan tidak ditemukan" });
  return res.status(403).json({ error: "Tidak diizinkan" });
}

// ── GET /api/jobs/saved — Harus sebelum /:id ─────────────────────────────
router.get("/saved", requireAuth, async (req, res, next) => {
  try {
    const { offset, to } = parsePagination(req.query, { defaultLimit: 50, maxLimit: 100 });
    const { data, error } = await supabase
      .from("saved_jobs")
      .select(`
        id, saved_at,
        job:job_id(
          id, title, company, company_logo, location, job_type,
          salary_min, salary_max, tags, apply_url, contact_email,
          poster:poster_id(id, user_profiles(full_name))
        )
      `)
      .eq("user_id", req.user.userId)
      .order("saved_at", { ascending: false })
      .range(offset, to);
    if (error) throw error;
    res.json({ data: (data || []).map((s) => s.job).filter(Boolean) });
  } catch (err) {
    next(err);
  }
});

// ── GET /api/jobs/my-jobs/all — Lowongan yang dibuat user sendiri ────────
router.get("/my-jobs/all", requireAuth, async (req, res, next) => {
  try {
    const { offset, to } = parsePagination(req.query, { defaultLimit: 50, maxLimit: 100 });
    const { data, error } = await supabase
      .from("jobs")
      .select(JOB_COLS)
      .eq("poster_id", req.user.userId)
      .order("created_at", { ascending: false })
      .range(offset, to);
    if (error) throw error;
    res.json({ data: data || [] });
  } catch (err) {
    next(err);
  }
});

// ── GET /api/jobs ─────────────────────────────────────────────────────────
router.get("/", async (req, res, next) => {
  try {
    const { q = "", type, is_remote } = req.query;
    const { page, limit, offset, to } = parsePagination(req.query);

    let dbQuery = supabase
      .from("jobs")
      .select(`
        id, poster_id, title, company, company_logo, location, job_type,
        salary_min, salary_max, tags, description, apply_url, contact_email, is_active, created_at,
        poster:poster_id(id, user_profiles(full_name, prodi, angkatan))
      `, { count: "exact" })
      .eq("is_active", true)
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .range(offset, to);

    const cleanQ = sanitizeSearch(q);
    if (cleanQ) dbQuery = dbQuery.or(`title.ilike.%${cleanQ}%,company.ilike.%${cleanQ}%`);
    if (typeof type === "string" && type.trim()) dbQuery = dbQuery.eq("job_type", type.trim());
    if (is_remote === "true") dbQuery = dbQuery.ilike("location", "%Remote%");

    const { data, count, error } = await dbQuery;
    if (error) throw error;
    res.json({ data, total: count, page, limit });
  } catch (err) {
    next(err);
  }
});

// ── GET /api/jobs/:id ─────────────────────────────────────────────────────
router.get("/:id", async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("jobs")
      .select(`${JOB_COLS}, poster:poster_id(id, user_profiles(full_name, avatar_url, prodi, angkatan))`)
      .eq("id", req.params.id)
      .maybeSingle();
    if (error) throw error;
    if (!data) return res.status(404).json({ error: "Lowongan tidak ditemukan" });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// ── POST /api/jobs — Post lowongan baru ───────────────────────────────────
router.post("/", requireAuth, async (req, res, next) => {
  try {
    const { errors, values } = buildJobFields(req.body || {}, true);
    if (errors.length) return res.status(400).json({ errors });

    const { data, error } = await supabase
      .from("jobs")
      .insert({
        poster_id: req.user.userId,
        ...values,
        company_logo: values.company_logo ?? null,
        job_type: values.job_type || "Full-time",
        salary_min: values.salary_min ?? null,
        salary_max: values.salary_max ?? null,
        tags: values.tags || [],
        description: values.description ?? null,
        apply_url: values.apply_url ?? null,
        contact_email: values.contact_email ?? null,
      })
      .select()
      .single();
    if (error) throw error;
    res.status(201).json(data);
  } catch (err) {
    next(err);
  }
});

// ── PUT /api/jobs/:id — Edit / Tutup / Aktifkan lowongan ──────────────────
router.put("/:id", requireAuth, async (req, res, next) => {
  try {
    const { errors, values } = buildJobFields(req.body || {}, false);
    if (errors.length) return res.status(400).json({ errors });
    if (Object.keys(values).length === 0) {
      return res.status(400).json({ error: "Tidak ada data yang diubah" });
    }

    const { data, error } = await supabase
      .from("jobs")
      .update(values)
      .eq("id", req.params.id)
      .eq("poster_id", req.user.userId)
      .select()
      .maybeSingle();
    if (error) throw error;
    if (!data) return await jobMissingOrForbidden(req.params.id, res);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// ── DELETE /api/jobs/:id — Hapus lowongan ─────────────────────────────────
router.delete("/:id", requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("jobs")
      .delete()
      .eq("id", req.params.id)
      .eq("poster_id", req.user.userId)
      .select("id");
    if (error) throw error;
    if (!data || data.length === 0) return await jobMissingOrForbidden(req.params.id, res);
    res.json({ message: "Lowongan dihapus" });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/jobs/:id/save — Toggle simpan ───────────────────────────────
router.post("/:id/save", requireAuth, async (req, res, next) => {
  try {
    const jobId = req.params.id;
    const userId = req.user.userId;

    // Atomic delete first: avoids check-then-act race conditions.
    const { data: removed, error: delErr } = await supabase
      .from("saved_jobs")
      .delete()
      .eq("job_id", jobId)
      .eq("user_id", userId)
      .select("id");
    if (delErr) throw delErr;
    if (removed && removed.length > 0) return res.json({ saved: false });

    const { error: insErr } = await supabase
      .from("saved_jobs")
      .insert({ job_id: jobId, user_id: userId });
    if (insErr) {
      if (isUniqueViolation(insErr)) return res.json({ saved: true });
      if (isFkViolation(insErr)) return res.status(404).json({ error: "Lowongan tidak ditemukan" });
      throw insErr;
    }
    res.json({ saved: true });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
