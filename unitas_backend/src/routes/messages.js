const express = require("express");
const { body, validationResult } = require("express-validator");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");
const { uuidParam, parsePagination, isFkViolation } = require("../lib/validate");

const router = express.Router();

router.param("peerId", uuidParam);

const MAX_MESSAGE_LENGTH = 4000;
// Panjang maksimal ciphertext base64 (≈ plaintext 4000 char + overhead enkripsi)
const MAX_CIPHERTEXT_LENGTH = 8000;

// Helper: verify two users are connected (accepted)
async function areConnected(userA, userB) {
  const { data, error } = await supabase
    .from("alumni_connections")
    .select("id")
    .eq("status", "accepted")
    .or(
      `and(requester_id.eq.${userA},addressee_id.eq.${userB}),and(requester_id.eq.${userB},addressee_id.eq.${userA})`
    )
    .limit(1);
  if (error) throw error;
  return Boolean(data && data.length > 0);
}

// ── GET /api/messages/conversations ───────────────────────────────────────
router.get("/conversations", requireAuth, async (req, res, next) => {
  try {
    const userId = req.user.userId;

    // Fetch accepted connections for this user
    const { data: conns, error: connErr } = await supabase
      .from("alumni_connections")
      .select(`
        requester:requester_id(id, user_profiles(full_name, initials, avatar_url, pekerjaan, perusahaan, is_online)),
        addressee:addressee_id(id, user_profiles(full_name, initials, avatar_url, pekerjaan, perusahaan, is_online))
      `)
      .eq("status", "accepted")
      .or(`requester_id.eq.${userId},addressee_id.eq.${userId}`)
      .limit(500);
    if (connErr) throw connErr;

    const peers = (conns || [])
      .map((c) => (c.requester?.id === userId ? c.addressee : c.requester))
      .filter(Boolean);

    if (peers.length === 0) {
      return res.json({ data: [], total_unread: 0 });
    }

    // Fetch latest messages, exact unread incoming rows, and peer public keys in parallel
    const peerIds = peers.map((p) => p.id);
    const [recentRes, unreadRes, keysRes] = await Promise.all([
      supabase
        .from("messages")
<<<<<<< Updated upstream
        .select("id, sender_id, receiver_id, content, ciphertext, is_read, created_at")
=======
        .select("id, sender_id, receiver_id, content, ciphertext, nonce, is_read, created_at")
>>>>>>> Stashed changes
        .or(`sender_id.eq.${userId},receiver_id.eq.${userId}`)
        .order("created_at", { ascending: false })
        .limit(500),
      supabase
        .from("messages")
        .select("sender_id")
        .eq("receiver_id", userId)
        .eq("is_read", false)
        .limit(1000),
      supabase
        .from("user_keys")
        .select("user_id, identity_public_key")
        .in("user_id", peerIds),
    ]);
    if (recentRes.error) throw recentRes.error;
    if (unreadRes.error) throw unreadRes.error;

    const keysByPeer = {};
    for (const k of keysRes.data || []) {
      keysByPeer[k.user_id] = k.identity_public_key;
    }

    const latestByPeer = {};
    for (const m of recentRes.data || []) {
      const peerId = m.sender_id === userId ? m.receiver_id : m.sender_id;
      if (!latestByPeer[peerId]) {
        latestByPeer[peerId] = m;
      }
    }

    const unreadByPeer = {};
    let totalUnread = 0;
    for (const row of unreadRes.data || []) {
      unreadByPeer[row.sender_id] = (unreadByPeer[row.sender_id] || 0) + 1;
      totalUnread++;
    }

    const conversations = peers.map((peer) => {
      const lastMsg = latestByPeer[peer.id] || null;
      // Jika pesan terakhir adalah E2EE (ada ciphertext), tampilkan label terenkripsi
      const lastMsgPreview = lastMsg
        ? (lastMsg.ciphertext ? "🔒 Pesan terenkripsi" : lastMsg.content)
        : null;
      return {
<<<<<<< Updated upstream
        peer,
        last_message: lastMsgPreview,
=======
        peer: {
          ...peer,
          identity_public_key: keysByPeer[peer.id] || null,
        },
        last_message: lastMsg ? (lastMsg.content || "🔒 Pesan terenkripsi") : null,
        last_message_ciphertext: lastMsg ? lastMsg.ciphertext : null,
        last_message_nonce: lastMsg ? lastMsg.nonce : null,
>>>>>>> Stashed changes
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

    if (userId === peerId) {
      return res.status(400).json({ error: "Tidak dapat membuka obrolan dengan diri sendiri" });
    }

    const connected = await areConnected(userId, peerId);
    if (!connected) {
      return res.status(403).json({ error: "Hanya bisa melihat pesan dari alumni yang sudah terkoneksi" });
    }

    const { limit } = parsePagination(req.query, { defaultLimit: 100, maxLimit: 200 });

    // Fetch newest `limit` messages DESC then reverse to chronological order so
    // threads with >100 messages always show the latest conversation instead of
    // getting stuck on the oldest 100.
    const { data, error } = await supabase
      .from("messages")
      .select("id, sender_id, receiver_id, content, ciphertext, nonce, sender_ratchet_public_key, ephemeral_public_key, message_number, previous_chain_length, is_read, created_at")
      .or(
        `and(sender_id.eq.${userId},receiver_id.eq.${peerId}),and(sender_id.eq.${peerId},receiver_id.eq.${userId})`
      )
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .limit(limit);
    if (error) throw error;

    const rows = (data || []).reverse();

    // Only issue the UPDATE write when there are actually unread incoming messages
    // (saves a DB write on every 4s chat poll).
    if (rows.some((m) => m.receiver_id === userId && !m.is_read)) {
      const { error: readErr } = await supabase
        .from("messages")
        .update({ is_read: true })
        .eq("sender_id", peerId)
        .eq("receiver_id", userId)
        .eq("is_read", false);
      if (readErr) console.error("Failed to mark messages as read:", readErr.message);
    }

    res.json({ data: rows });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/messages/:peerId ────────────────────────────────────────────
router.post(
  "/:peerId",
  requireAuth,
  [
    // E2EE mode: ciphertext wajib ada
    // Legacy mode: content wajib ada
    // Setidaknya satu dari keduanya harus ada
    body("ciphertext")
      .optional()
      .isString()
      .isLength({ max: MAX_CIPHERTEXT_LENGTH })
      .withMessage(`Ciphertext maksimal ${MAX_CIPHERTEXT_LENGTH} karakter`),
    body("content")
      .optional()
      .isString()
      .trim()
      .isLength({ max: MAX_MESSAGE_LENGTH })
      .withMessage(`Pesan maksimal ${MAX_MESSAGE_LENGTH} karakter`),
    body("nonce").optional().isString(),
    body("sender_ratchet_public_key").optional().isString(),
    body("ephemeral_public_key").optional().isString(),
    body("message_number").optional().isInt({ min: 0 }),
    body("previous_chain_length").optional().isInt({ min: 0 }),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    const { content, ciphertext, nonce, sender_ratchet_public_key, ephemeral_public_key, message_number, previous_chain_length } = req.body;

    // Harus ada salah satu: ciphertext (E2EE) atau content (legacy)
    if (!ciphertext && !content) {
      return res.status(400).json({ errors: [{ msg: "Pesan tidak boleh kosong" }] });
    }

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

      // Bangun objek insert — backend hanya relay, tidak melihat isi pesan
      const insertPayload = {
        sender_id: userId,
        receiver_id: peerId,
      };

      if (ciphertext) {
        // Mode E2EE
        insertPayload.ciphertext = ciphertext;
        insertPayload.nonce = nonce;
        insertPayload.sender_ratchet_public_key = sender_ratchet_public_key;
        insertPayload.ephemeral_public_key = ephemeral_public_key || null;
        insertPayload.message_number = message_number ?? 0;
        insertPayload.previous_chain_length = previous_chain_length ?? 0;
        // content tetap null — tidak ada plaintext
      } else {
        // Legacy mode (backward compat untuk pesan lama / testing)
        insertPayload.content = content;
      }

      const { data, error } = await supabase
        .from("messages")
        .insert(insertPayload)
        .select("id, sender_id, receiver_id, content, ciphertext, nonce, sender_ratchet_public_key, ephemeral_public_key, message_number, previous_chain_length, is_read, created_at")
        .single();
      if (error) {
        if (isFkViolation(error)) return res.status(404).json({ error: "Pengguna tidak ditemukan" });
        throw error;
      }

      res.status(201).json(data);
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
