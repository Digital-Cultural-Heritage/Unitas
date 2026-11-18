const express = require("express");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");
const { uuidParam, parsePagination } = require("../lib/validate");

const router = express.Router();

router.param("id", uuidParam);

// ── GET /api/notifications ────────────────────────────────────────────────
router.get("/", requireAuth, async (req, res, next) => {
  try {
    const { offset, to } = parsePagination(req.query, { defaultLimit: 30, maxLimit: 100 });
    const userId = req.user.userId;

    const [listRes, unreadRes] = await Promise.all([
      supabase
        .from("notifications")
        .select(`
          id, type, title, body, reference_id, is_read, created_at,
          actor:actor_id(id, user_profiles(full_name, initials, avatar_url))
        `)
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .range(offset, to),
      supabase
        .from("notifications")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .eq("is_read", false),
    ]);

    if (listRes.error) throw listRes.error;
    if (unreadRes.error) throw unreadRes.error;
    res.json({ data: listRes.data || [], unread_count: unreadRes.count || 0 });
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
    const { data, error } = await supabase
      .from("notifications")
      .update({ is_read: true })
      .eq("id", req.params.id)
      .eq("user_id", req.user.userId)
      .select("id")
      .maybeSingle();
    if (error) throw error;
    if (!data) return res.status(404).json({ error: "Notifikasi tidak ditemukan" });
    res.json({ message: "Notifikasi ditandai sudah dibaca" });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
