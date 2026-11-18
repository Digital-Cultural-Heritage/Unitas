const express = require("express");
const { body, query, validationResult } = require("express-validator");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");
const { createNotification } = require("../lib/notifications");
const { verifyAccessToken } = require("../lib/jwt");

const router = express.Router();

// -- GET /api/users/me ----------------------------------------------------
router.get("/me", requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("users")
      .select("id, email, role, user_profiles(*)")
      .eq("id", req.user.userId)
      .single();
    if (error) throw error;

    const rawProfile = data.user_profiles;
    const profile = (Array.isArray(rawProfile) ? rawProfile[0] : rawProfile) || {};
    res.json({ id: data.id, email: data.email, role: data.role, ...profile });
  } catch (err) {
    next(err);
  }
});

// -- PUT /api/users/me ----------------------------------------------------
router.put("/me", requireAuth, async (req, res, next) => {
  try {
    const allowed = ["full_name", "bio", "prodi", "angkatan", "kota", "pekerjaan", "perusahaan", "linkedin"];
    const updates = {};
    allowed.forEach((f) => { if (req.body[f] !== undefined) updates[f] = req.body[f]; });
    updates.updated_at = new Date().toISOString();

    const { data, error } = await supabase
      .from("user_profiles")
      .update(updates)
      .eq("user_id", req.user.userId)
      .select()
      .single();
    if (error) throw error;
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// -- GET /api/users � Direktori alumni ------------------------------------
router.get("/", async (req, res, next) => {
  try {
    const { q = "", prodi, kota, is_online, page = 1, limit = 20 } = req.query;
    const offset = (Number(page) - 1) * Number(limit);

    let dbQuery = supabase
      .from("user_profiles")
      .select("user_id, full_name, initials, avatar_url, prodi, angkatan, kota, pekerjaan, perusahaan, is_online, points", { count: "exact" })
      .order("points", { ascending: false })
      .range(offset, offset + Number(limit) - 1);

    if (q) {
      dbQuery = dbQuery.or(`full_name.ilike.%${q}%,prodi.ilike.%${q}%,perusahaan.ilike.%${q}%`);
    }
    if (prodi)     dbQuery = dbQuery.eq("prodi", prodi);
    if (kota)      dbQuery = dbQuery.eq("kota", kota);
    if (is_online === "true") dbQuery = dbQuery.eq("is_online", true);

    const { data, count, error } = await dbQuery;
    if (error) throw error;

    let statusMap = {};
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith("Bearer ") && data && data.length > 0) {
      try {
        const decoded = verifyAccessToken(authHeader.split(" ")[1]);
        const currentUserId = decoded.userId;
        const { data: conns } = await supabase
          .from("alumni_connections")
          .select("requester_id, addressee_id, status")
          .or(`requester_id.eq.${currentUserId},addressee_id.eq.${currentUserId}`);

        if (conns) {
          for (const c of conns) {
            const otherId = c.requester_id === currentUserId ? c.addressee_id : c.requester_id;
            if (c.status === "accepted") {
              statusMap[otherId] = "accepted";
            } else if (c.status === "pending") {
              statusMap[otherId] = c.requester_id === currentUserId ? "pending" : "incoming";
            }
          }
        }
      } catch (_) {}
    }

    const enriched = (data || []).map((row) => ({
      ...row,
      connection_status: statusMap[row.user_id] || "none",
    }));

    res.json({ data: enriched, total: count, page: Number(page), limit: Number(limit) });
  } catch (err) {
    next(err);
  }
});

// -- GET /api/users/:id ---------------------------------------------------
router.get("/:id", async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("user_profiles")
      .select("*")
      .eq("user_id", req.params.id)
      .single();
    if (error || !data) return res.status(404).json({ error: "Alumni tidak ditemukan" });

    let connection_status = "none";
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith("Bearer ")) {
      try {
        const decoded = verifyAccessToken(authHeader.split(" ")[1]);
        const currentUserId = decoded.userId;
        if (currentUserId !== req.params.id) {
          const { data: conn } = await supabase
            .from("alumni_connections")
            .select("requester_id, addressee_id, status")
            .or(
              `and(requester_id.eq.${currentUserId},addressee_id.eq.${req.params.id}),` +
              `and(requester_id.eq.${req.params.id},addressee_id.eq.${currentUserId})`
            )
            .limit(1)
            .single();
          if (conn) {
            if (conn.status === "accepted") connection_status = "accepted";
            else if (conn.status === "pending") {
              connection_status = conn.requester_id === currentUserId ? "pending" : "incoming";
            }
          }
        }
      } catch (_) {}
    }

    res.json({ ...data, connection_status });
  } catch (err) {
    next(err);
  }
});

// -- POST /api/users/:id/connect ------------------------------------------
router.post("/:id/connect", requireAuth, async (req, res, next) => {
  try {
    const { id: addresseeId } = req.params;
    const requesterId = req.user.userId;

    if (requesterId === addresseeId) {
      return res.status(400).json({ error: "Tidak bisa menghubungi diri sendiri" });
    }

    // Cek sudah ada koneksi
    const { data: existing } = await supabase
      .from("alumni_connections")
      .select("id, status, requester_id")
      .or(
        `and(requester_id.eq.${requesterId},addressee_id.eq.${addresseeId}),` +
        `and(requester_id.eq.${addresseeId},addressee_id.eq.${requesterId})`
      )
      .single();

    if (existing) {
      if (existing.status === "accepted") {
        return res.json({ message: "Sudah terhubung", connection: existing });
      }

      // Jika pengirim yang sama menekan lagi, jangan auto-accept permintaan sendiri
      if (existing.status === "pending" && existing.requester_id === requesterId) {
        return res.json({ message: "Permintaan koneksi sudah dikirim", connection: existing });
      }

      // Setujui jika ada pending dari sisi lain
      if (existing.status === "pending") {
        const { data: updated, error } = await supabase
          .from("alumni_connections")
          .update({ status: "accepted" })
          .eq("id", existing.id)
          .select()
          .single();
        if (error) throw error;
        return res.json({ message: "Koneksi diterima", connection: updated });
      }
    }

    // Buat permintaan baru
    const { data, error } = await supabase
      .from("alumni_connections")
      .insert({ requester_id: requesterId, addressee_id: addresseeId })
      .select()
      .single();
    if (error) throw error;

    const { data: actorProfile } = await supabase
      .from("user_profiles")
      .select("full_name")
      .eq("user_id", requesterId)
      .single();
    await createNotification({
      userId: addresseeId,
      actorId: requesterId,
      type: "connection_request",
      title: `${actorProfile?.full_name || "Alumni"} mengirim permintaan koneksi`,
      referenceId: data.id,
    });

    res.status(201).json({ message: "Permintaan koneksi dikirim", connection: data });
  } catch (err) {
    next(err);
  }
});

// -- GET /api/users/me/connections ----------------------------------------
router.get("/me/connections", requireAuth, async (req, res, next) => {
  try {
    const userId = req.user.userId;
    const { data, error } = await supabase
      .from("alumni_connections")
      .select(`
        id, status, created_at,
        requester:requester_id(user_id:id, user_profiles(full_name, avatar_url, pekerjaan, perusahaan)),
        addressee:addressee_id(user_id:id, user_profiles(full_name, avatar_url, pekerjaan, perusahaan))
      `)
      .or(`requester_id.eq.${userId},addressee_id.eq.${userId}`)
      .eq("status", "accepted");
    if (error) throw error;
    res.json({ data });
  } catch (err) {
    next(err);
  }
});


// -- GET /api/users/me/requests -------------------------------------------
router.get("/me/requests", requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("alumni_connections")
      .select(`
        id, created_at,
        requester:requester_id(id, user_profiles(full_name, avatar_url, prodi, angkatan))
      `)
      .eq("addressee_id", req.user.userId)
      .eq("status", "pending")
      .order("created_at", { ascending: false });
    if (error) throw error;
    res.json({ data });
  } catch (err) {
    next(err);
  }
});

// -- PUT /api/users/requests/:id ------------------------------------------
router.put("/requests/:id", requireAuth, async (req, res, next) => {
  try {
    const { action } = req.body; // 'accept' or 'reject'
    const status = action === 'accept' ? 'accepted' : 'rejected';
    const { data, error } = await supabase
      .from("alumni_connections")
      .update({ status })
      .eq("id", req.params.id)
      .eq("addressee_id", req.user.userId)
      .select()
      .single();
    if (error) throw error;
    if (status === "accepted" && data) {
      const { data: actorProfile } = await supabase
        .from("user_profiles")
        .select("full_name")
        .eq("user_id", req.user.userId)
        .single();
      await createNotification({
        userId: data.requester_id,
        actorId: req.user.userId,
        type: "connection_accepted",
        title: `${actorProfile?.full_name || "Alumni"} menerima permintaan koneksimu`,
        referenceId: data.id,
      });
    }
    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

