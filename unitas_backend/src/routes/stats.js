const express = require("express");
const supabase = require("../lib/supabase");

const router = express.Router();

// ── GET /api/stats ────────────────────────────────────────────────────────
router.get("/", async (req, res, next) => {
  try {
    const today = new Date().toISOString().split("T")[0];

    const [alumniRes, eventsRes, activeEventsRes, jobsRes] = await Promise.all([
      supabase.from("users").select("id", { count: "exact", head: true }),
      supabase.from("events").select("id", { count: "exact", head: true }),
      supabase.from("events").select("id", { count: "exact", head: true }).gte("event_date", today),
      supabase.from("jobs").select("id", { count: "exact", head: true }).eq("is_active", true),
    ]);

    const firstErr = alumniRes.error || eventsRes.error || activeEventsRes.error || jobsRes.error;
    if (firstErr) throw firstErr;

    res.json({
      total_alumni: alumniRes.count || 0,
      total_events: eventsRes.count || 0,
      active_events: activeEventsRes.count || 0,
      total_jobs: jobsRes.count || 0,
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
