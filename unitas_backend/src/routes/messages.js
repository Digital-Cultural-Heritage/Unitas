const express = require("express");
const { body, validationResult } = require("express-validator");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");

const router = express.Router();

// Helper: verify two users are connected (accepted)
async function areConnected(userA, userB) {
  const { data } = await supabase
    .from("alumni_connections")
    .select("id")
    .eq("status", "accepted")
    .or(
      `and(requester_id.eq.${userA},addressee_id.eq.${userB}),and(requester_id.eq.${userB},addressee_id.eq.${userA})`
    )
    .limit(1);
  return (data && data.length > 0);
}

// ── GET /api/messages/conversations ───────────────────────────────────────
router.get("/conversations", requireAuth, async (req, res, next) => {
  try {
    const userId = req.user.userId;

    // Fetch all accepted connections
    const { data: conns, error: connErr } = await supabase
      .from("alumni_connections")
      .select(`
        requester:requester_id(id, user_profiles(full_name, initials, avatar_url, pekerjaan, perusahaan, is_online)),
        addressee:addressee_id(id, user_profiles(full_name, initials, avatar_url, pekerjaan, perusahaan, is_online))
      `)
      .eq("status", "accepted")
      .or(`requester_id.eq.${userId},addressee_id.eq.${userId}`);
    if (connErr) throw connErr;

    const peers = (conns || []).map((c) =>
      c.requester?.id === userId ? c.addressee : c.requester
    ).filter(Boolean);

    // Fetch recent messages involving current user
    const { data: msgs, error: msgErr } = await supabase
      .from("messages")
      .select("id, sender_id, receiver_id, content, is_read, created_at")
      .or(`sender_id.eq.${userId},receiver_id.eq.${userId}`)
      .order("created_at", { ascending: false })
      .limit(300);
    if (msgErr) throw msgErr;

    const latestByPeer = {};
    const unreadByPeer = {};

    for (const m of msgs || []) {
      const peerId = m.sender_id === userId ? m.receiver_id : m.sender_id;
      if (!latestByPeer[peerId]) {
        latestByPeer[peerId] = m;
      }
      if (m.receiver_id === userId && !m.is_read) {
        unreadByPeer[peerId] = (unreadByPeer[peerId] || 0) + 1;
      }
    }

    const conversations = peers.map((peer) => {
      const lastMsg = latestByPeer[peer.id] || null;
      return {
        peer,
        last_message: lastMsg ? lastMsg.content : null,
        last_message_at: lastMsg ? lastMsg.created_at : null,
        unread_count: unreadByPeer[peer.id] || 0,
      };
    });

    conversations.sort((a, b) => {
      if (!a.last_message_at && !b.last_message_at) return 0;
      if (!a.last_message_at) return 1;
      if (!b.last_message_at) return -1;
      return new Date(b.last_message_at) - new Date(a.last_message_at);
    });

    const totalUnread = Object.values(unreadByPeer).reduce((acc, v) => acc + v, 0);
    res.json({ data: conversations, total_unread: totalUnread });
  } catch (err) {
    next(err);
  }
});

// ── GET /api/messages/:peerId ─────────────────────────────────────────────
router.get("/:peerId", requireAuth, async (req, res, next) => {
  try {
    const userId = req.user.userId;
    const peerId = req.params.peerId;

    const { data, error } = await supabase
      .from("messages")
      .select("id, sender_id, receiver_id, content, is_read, created_at")
      .or(
        `and(sender_id.eq.${userId},receiver_id.eq.${peerId}),and(sender_id.eq.${peerId},receiver_id.eq.${userId})`
      )
      .order("created_at", { ascending: true })
      .limit(100);
    if (error) throw error;

    // Mark incoming messages as read
    await supabase
      .from("messages")
      .update({ is_read: true })
      .eq("sender_id", peerId)
      .eq("receiver_id", userId)
      .eq("is_read", false);

    res.json({ data: data || [] });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/messages/:peerId ────────────────────────────────────────────
router.post(
  "/:peerId",
  requireAuth,
  [body("content").trim().notEmpty().withMessage("Pesan tidak boleh kosong")],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    try {
      const userId = req.user.userId;
      const peerId = req.params.peerId;

      if (userId === peerId) {
        return res.status(400).json({ error: "Tidak dapat mengirim pesan ke diri sendiri" });
      }

      const connected = await areConnected(userId, peerId);
      if (!connected) {
        return res.status(403).json({ error: "Hanya bisa mengirim pesan ke alumni yang sudah terkoneksi" });
      }

      const { data, error } = await supabase
        .from("messages")
        .insert({
          sender_id: userId,
          receiver_id: peerId,
          content: req.body.content.trim(),
        })
        .select("id, sender_id, receiver_id, content, is_read, created_at")
        .single();
      if (error) throw error;

      res.status(201).json(data);
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
