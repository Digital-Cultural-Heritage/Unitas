const express = require("express");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");

const router = express.Router();

// ── GET /api/notifications ────────────────────────────────────────────────
router.get("/", requireAuth, async (req, res, next) => {
  try {
    const { limit = 30 } = req.query;
    const userId = req.user.userId;

    const [{ data, error }, { count: unreadCount }] = await Promise.all([
      supabase
        .from("notifications")
        .select(`
          id, type, title, body, reference_id, is_read, created_at,
          actor:actor_id(id, user_profiles(full_name, initials, avatar_url))
        `)
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(Number(limit)),
      supabase
        .from("notifications")
        .select("*", { count: "exact", head: true })
        .eq("user_id", userId)
        .eq("is_read", false),
    ]);

    if (error) throw error;
    res.json({ data: data || [], unread_count: unreadCount || 0 });
  } catch (err) {
    next(err);
  }
});

// ── PUT /api/notifications/read-all ───────────────────────────────────────
router.put("/read-all", requireAuth, async (req, res, next) => {
  try {
    const { error } = await supabase
      .from("notifications")
      .update({ is_read: true })
      .eq("user_id", req.user.userId)
      .eq("is_read", false);
    if (error) throw error;
    res.json({ message: "Semua notifikasi ditandai sudah dibaca" });
  } catch (err) {
    next(err);
  }
});

// ── PUT /api/notifications/:id/read ───────────────────────────────────────
router.put("/:id/read", requireAuth, async (req, res, next) => {
  try {
    const { error } = await supabase
      .from("notifications")
      .update({ is_read: true })
      .eq("id", req.params.id)
      .eq("user_id", req.user.userId);
    if (error) throw error;
    res.json({ message: "Notifikasi ditandai sudah dibaca" });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
