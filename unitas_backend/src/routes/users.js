const express = require("express");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");
const { createNotification } = require("../lib/notifications");
const { verifyAccessToken } = require("../lib/jwt");
const {
  isUuid,
  uuidParam,
  parsePagination,
  sanitizeSearch,
  isHttpUrl,
  isUniqueViolation,
  isFkViolation,
} = require("../lib/validate");

const router = express.Router();

router.param("id", uuidParam);

function optionalUserId(req) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) return null;
  try {
    const decoded = verifyAccessToken(authHeader.split(" ")[1]);
    return isUuid(decoded?.userId) ? decoded.userId : null;
  } catch (_) {
    return null;
  }
}

async function getActorName(userId) {
  const { data } = await supabase
    .from("user_profiles")
    .select("full_name")
    .eq("user_id", userId)
    .maybeSingle();
  return data?.full_name || "Alumni";
}

function buildProfileUpdates(body) {
  const errors = [];
  const updates = {};
  const has = (k) => body[k] !== undefined;

  if (has("full_name")) {
    if (typeof body.full_name !== "string" || !body.full_name.trim() || body.full_name.trim().length > 100) {
      errors.push({ msg: "Nama lengkap wajib diisi (maks 100 karakter)", path: "full_name" });
    } else {
      updates.full_name = body.full_name.trim();
    }
  }

  if (has("bio")) {
    if (body.bio === null || body.bio === "") updates.bio = null;
    else if (typeof body.bio === "string" && body.bio.trim().length <= 2000) {
      updates.bio = body.bio.trim() || null;
    } else {
      errors.push({ msg: "Bio maksimal 2000 karakter", path: "bio" });
    }
  }

  for (const key of ["prodi", "kota", "pekerjaan", "perusahaan"]) {
    if (has(key)) {
      const v = body[key];
      if (v === null || v === "") updates[key] = null;
      else if (typeof v === "string" && v.trim().length <= 100) {
        updates[key] = v.trim() || null;
      } else {
        errors.push({ msg: `${key} maksimal 100 karakter`, path: key });
      }
    }
  }

  if (has("angkatan")) {
    const v = body.angkatan;
    if (v === null || v === "") updates.angkatan = null;
    else if ((typeof v === "string" || typeof v === "number") && String(v).trim().length <= 20) {
      updates.angkatan = String(v).trim() || null;
    } else {
      errors.push({ msg: "Angkatan tidak valid", path: "angkatan" });
    }
  }

  if (has("linkedin")) {
    const v = body.linkedin;
    if (v === null || v === "") updates.linkedin = null;
    else if (typeof v === "string" && isHttpUrl(v.trim())) updates.linkedin = v.trim();
    else errors.push({ msg: "URL LinkedIn harus diawali http:// atau https://", path: "linkedin" });
  }

  return { errors, updates };
}

// -- GET /api/users/me ----------------------------------------------------
router.get("/me", requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("users")
      .select("id, email, role, password_hash, user_profiles(*)")
      .eq("id", req.user.userId)
      .maybeSingle();
    if (error) throw error;
    if (!data) return res.status(404).json({ error: "User tidak ditemukan" });

    const rawProfile = data.user_profiles;
    const profile = (Array.isArray(rawProfile) ? rawProfile[0] : rawProfile) || {};
    res.json({
      ...profile,
      id: data.id,
      email: data.email,
      role: data.role,
      has_password: typeof data.password_hash === "string" && data.password_hash.startsWith("$2"),
    });
  } catch (err) {
    next(err);
  }
});

// -- PUT /api/users/me ----------------------------------------------------
router.put("/me", requireAuth, async (req, res, next) => {
  try {
    const { errors, updates } = buildProfileUpdates(req.body || {});
    if (errors.length) return res.status(400).json({ errors });
    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: "Tidak ada data yang diubah" });
    }

    updates.updated_at = new Date().toISOString();

    const { data, error } = await supabase
      .from("user_profiles")
      .update(updates)
      .eq("user_id", req.user.userId)
      .select()
      .maybeSingle();
    if (error) throw error;
    if (!data) return res.status(404).json({ error: "Profil tidak ditemukan" });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// -- DELETE /api/users/me -------------------------------------------------
router.delete("/me", requireAuth, async (req, res, next) => {
  try {
    const { data: user, error } = await supabase
      .from("users")
      .select("id, refresh_token")
      .eq("id", req.user.userId)
      .maybeSingle();
    if (error) throw error;
    if (!user) return res.status(404).json({ error: "User tidak ditemukan" });
    if (!user.refresh_token) {
      return res.status(401).json({ error: "Sesi sudah berakhir. Silakan masuk kembali." });
    }

    const { error: delErr } = await supabase.from("users").delete().eq("id", user.id);
    if (delErr) throw delErr;
    res.json({ message: "Akun berhasil dihapus" });
  } catch (err) {
    next(err);
  }
});

// -- GET /api/users/me/connections ----------------------------------------
router.get("/me/connections", requireAuth, async (req, res, next) => {
  try {
    const userId = req.user.userId;
    const { offset, to } = parsePagination(req.query, { defaultLimit: 100, maxLimit: 200 });
    const { data, error } = await supabase
      .from("alumni_connections")
      .select(`
        id, status, created_at,
        requester:requester_id(user_id:id, user_profiles(full_name, avatar_url, pekerjaan, perusahaan)),
        addressee:addressee_id(user_id:id, user_profiles(full_name, avatar_url, pekerjaan, perusahaan))
      `)
      .or(`requester_id.eq.${userId},addressee_id.eq.${userId}`)
      .eq("status", "accepted")
      .order("created_at", { ascending: false })
      .range(offset, to);
    if (error) throw error;
    res.json({ data });
  } catch (err) {
    next(err);
  }
});

// -- GET /api/users/me/requests -------------------------------------------
router.get("/me/requests", requireAuth, async (req, res, next) => {
  try {
    const { offset, to } = parsePagination(req.query, { defaultLimit: 50, maxLimit: 100 });
    const { data, error } = await supabase
      .from("alumni_connections")
      .select(`
        id, created_at,
        requester:requester_id(id, user_profiles(full_name, avatar_url, prodi, angkatan))
      `)
      .eq("addressee_id", req.user.userId)
      .eq("status", "pending")
      .order("created_at", { ascending: false })
      .range(offset, to);
    if (error) throw error;
    res.json({ data });
  } catch (err) {
    next(err);
  }
});

// -- PUT /api/users/requests/:id ------------------------------------------
router.put("/requests/:id", requireAuth, async (req, res, next) => {
  try {
    const action = req.body?.action;
    if (action !== "accept" && action !== "reject") {
      return res.status(400).json({ error: "action harus 'accept' atau 'reject'" });
    }
    const status = action === "accept" ? "accepted" : "rejected";

    // Only transition pending requests belonging to the addressee.
    const { data, error } = await supabase
      .from("alumni_connections")
      .update({ status })
      .eq("id", req.params.id)
      .eq("addressee_id", req.user.userId)
      .eq("status", "pending")
      .select()
      .maybeSingle();
    if (error) throw error;

    if (!data) {
      const { data: existing, error: fetchErr } = await supabase
        .from("alumni_connections")
        .select("id, addressee_id, status")
        .eq("id", req.params.id)
        .maybeSingle();
      if (fetchErr) throw fetchErr;
      if (!existing || existing.addressee_id !== req.user.userId) {
        return res.status(404).json({ error: "Permintaan koneksi tidak ditemukan" });
      }
      return res.status(409).json({ error: "Permintaan koneksi sudah diproses" });
    }

    if (status === "accepted") {
      const actorName = await getActorName(req.user.userId);
      await createNotification({
        userId: data.requester_id,
        actorId: req.user.userId,
        type: "connection_accepted",
        title: `${actorName} menerima permintaan koneksimu`,
        referenceId: data.id,
      });
    }
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// -- GET /api/users - Direktori alumni ------------------------------------
router.get("/", async (req, res, next) => {
  try {
    const { q = "", prodi, kota, is_online } = req.query;
    const { page, limit, offset, to } = parsePagination(req.query);

    let dbQuery = supabase
      .from("user_profiles")
      .select(
        "user_id, full_name, initials, avatar_url, prodi, angkatan, kota, pekerjaan, perusahaan, is_online, points",
        { count: "exact" }
      )
      .order("points", { ascending: false })
      .order("user_id", { ascending: true })
      .range(offset, to);

    const cleanQ = sanitizeSearch(q);
    if (cleanQ) {
      dbQuery = dbQuery.or(`full_name.ilike.%${cleanQ}%,prodi.ilike.%${cleanQ}%,perusahaan.ilike.%${cleanQ}%`);
    }
    if (typeof prodi === "string" && prodi.trim()) dbQuery = dbQuery.eq("prodi", prodi.trim());
    if (typeof kota === "string" && kota.trim()) dbQuery = dbQuery.eq("kota", kota.trim());
    if (is_online === "true") dbQuery = dbQuery.eq("is_online", true);

    const { data, count, error } = await dbQuery;
    if (error) throw error;

    const statusMap = {};
    const currentUserId = optionalUserId(req);
    const pageUserIds = (data || []).map((r) => r.user_id).filter(isUuid);

    if (currentUserId && pageUserIds.length > 0) {
      const idList = pageUserIds.join(",");
      const { data: conns, error: connErr } = await supabase
        .from("alumni_connections")
        .select("requester_id, addressee_id, status")
        .in("status", ["accepted", "pending"])
        .or(
          `and(requester_id.eq.${currentUserId},addressee_id.in.(${idList})),` +
          `and(addressee_id.eq.${currentUserId},requester_id.in.(${idList}))`
        );
      if (!connErr && conns) {
        for (const c of conns) {
          const otherId = c.requester_id === currentUserId ? c.addressee_id : c.requester_id;
          if (c.status === "accepted") {
            statusMap[otherId] = "accepted";
          } else if (c.status === "pending") {
            statusMap[otherId] = c.requester_id === currentUserId ? "pending" : "incoming";
          }
        }
      }
    }

    const enriched = (data || []).map((row) => ({
      ...row,
      connection_status: statusMap[row.user_id] || "none",
    }));

    res.json({ data: enriched, total: count, page, limit });
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
      .maybeSingle();
    if (error) throw error;
    if (!data) return res.status(404).json({ error: "Alumni tidak ditemukan" });

    let connection_status = "none";
    const currentUserId = optionalUserId(req);
    if (currentUserId && currentUserId !== req.params.id) {
      const { data: conn, error: connErr } = await supabase
        .from("alumni_connections")
        .select("requester_id, addressee_id, status")
        .in("status", ["accepted", "pending"])
        .or(
          `and(requester_id.eq.${currentUserId},addressee_id.eq.${req.params.id}),` +
          `and(requester_id.eq.${req.params.id},addressee_id.eq.${currentUserId})`
        )
        .limit(1)
        .maybeSingle();
      if (!connErr && conn) {
        if (conn.status === "accepted") connection_status = "accepted";
        else if (conn.status === "pending") {
          connection_status = conn.requester_id === currentUserId ? "pending" : "incoming";
        }
      }
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

    // Cek sudah ada koneksi (dua arah)
    const { data: existing, error: fetchErr } = await supabase
      .from("alumni_connections")
      .select("id, status, requester_id, addressee_id")
      .or(
        `and(requester_id.eq.${requesterId},addressee_id.eq.${addresseeId}),` +
        `and(requester_id.eq.${addresseeId},addressee_id.eq.${requesterId})`
      )
      .limit(1)
      .maybeSingle();
    if (fetchErr) throw fetchErr;

    if (existing) {
      if (existing.status === "accepted") {
        return res.json({ message: "Sudah terhubung", connection: existing });
      }

      // Jika pengirim yang sama menekan lagi, jangan auto-accept permintaan sendiri
      if (existing.status === "pending" && existing.requester_id === requesterId) {
        return res.json({ message: "Permintaan koneksi sudah dikirim", connection: existing });
      }

      // Setujui jika ada pending dari sisi lain (transisi atomik)
      if (existing.status === "pending") {
        const { data: updated, error } = await supabase
          .from("alumni_connections")
          .update({ status: "accepted" })
          .eq("id", existing.id)
          .eq("status", "pending")
          .select()
          .maybeSingle();
        if (error) throw error;
        if (!updated) {
          return res.json({ message: "Sudah terhubung", connection: existing });
        }

        const actorName = await getActorName(requesterId);
        await createNotification({
          userId: existing.requester_id,
          actorId: requesterId,
          type: "connection_accepted",
          title: `${actorName} menerima permintaan koneksimu`,
          referenceId: updated.id,
        });
        return res.json({ message: "Koneksi diterima", connection: updated });
      }

      // Previously rejected
      if (existing.status === "rejected") {
        if (existing.requester_id === requesterId) {
          return res.status(409).json({ error: "Permintaan koneksi sebelumnya ditolak" });
        }
        // Rejector now initiates connection -> reuse the row as a fresh pending request
        const { data: reopened, error: reopenErr } = await supabase
          .from("alumni_connections")
          .update({ requester_id: requesterId, addressee_id: addresseeId, status: "pending" })
          .eq("id", existing.id)
          .eq("status", "rejected")
          .select()
          .single();
        if (reopenErr) throw reopenErr;

        const actorName = await getActorName(requesterId);
        await createNotification({
          userId: addresseeId,
          actorId: requesterId,
          type: "connection_request",
          title: `${actorName} mengirim permintaan koneksi`,
          referenceId: reopened.id,
        });
        return res.status(201).json({ message: "Permintaan koneksi dikirim", connection: reopened });
      }
    }

    // Buat permintaan baru
    const { data, error } = await supabase
      .from("alumni_connections")
      .insert({ requester_id: requesterId, addressee_id: addresseeId })
      .select()
      .single();
    if (error) {
      if (isFkViolation(error)) return res.status(404).json({ error: "Alumni tidak ditemukan" });
      if (isUniqueViolation(error)) {
        return res.status(409).json({ error: "Permintaan koneksi sudah dikirim" });
      }
      throw error;
    }

    const actorName = await getActorName(requesterId);
    await createNotification({
      userId: addresseeId,
      actorId: requesterId,
      type: "connection_request",
      title: `${actorName} mengirim permintaan koneksi`,
      referenceId: data.id,
    });

    res.status(201).json({ message: "Permintaan koneksi dikirim", connection: data });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
