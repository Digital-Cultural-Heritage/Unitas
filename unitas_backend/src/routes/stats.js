const express = require("express");
const supabase = require("../lib/supabase");

const router = express.Router();

// ── GET /api/stats ────────────────────────────────────────────────────────
router.get("/", async (req, res, next) => {
  try {
    const today = new Date().toISOString().split("T")[0];

    const [
      { count: totalAlumni },
      { count: totalEvents },
      { count: activeEvents },
      { count: totalJobs },
    ] = await Promise.all([
      supabase.from("users").select("*", { count: "exact", head: true }),
      supabase.from("events").select("*", { count: "exact", head: true }),
      supabase.from("events").select("*", { count: "exact", head: true }).gte("event_date", today),
      supabase.from("jobs").select("*", { count: "exact", head: true }).eq("is_active", true),
    ]);

    res.json({
      total_alumni: totalAlumni || 0,
      total_events: totalEvents || 0,
      active_events: activeEvents || 0,
      total_jobs: totalJobs || 0,
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
