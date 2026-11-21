const express = require("express");
const { body, validationResult } = require("express-validator");
const supabase = require("../lib/supabase");
const { requireAuth, resolveOptionalViewerId } = require("../middleware/auth");
const { createNotification } = require("../lib/notifications");
const {
  uuidParam,
  parsePagination,
  isHttpUrl,
  isUniqueViolation,
  isFkViolation,
  isUuid,
} = require("../lib/validate");

const router = express.Router();

// Reject malformed UUIDs early (404) instead of a Postgres 22P02 -> 500.
router.param("id", uuidParam);
router.param("commentId", uuidParam);

const MAX_POST_LENGTH = 5000;
const MAX_COMMENT_LENGTH = 2000;

// Award points without ever failing the main request.
async function awardPoints(userId, pts) {
  try {
    const { error } = await supabase.rpc("increment_points", { uid: userId, pts });
    if (error) console.error("increment_points failed:", error.message);
  } catch (err) {
    console.error("increment_points failed:", err.message);
  }
}

function profileName(user) {
  const p = user?.user_profiles;
  const profile = Array.isArray(p) ? p[0] : p;
  return profile?.full_name;
}

// Distinguish 404 vs 403 after an owner-scoped write matched no rows.
async function postMissingOrForbidden(postId, res) {
  const { data: post } = await supabase.from("posts").select("id").eq("id", postId).maybeSingle();
  if (!post) return res.status(404).json({ error: "Post tidak ditemukan" });
  return res.status(403).json({ error: "Tidak diizinkan" });
}

async function fetchPostLikesCount(postId) {
  const { data: post, error } = await supabase
    .from("posts")
    .select("likes_count")
    .eq("id", postId)
    .maybeSingle();
  if (error) throw error;
  return post ? Math.max(0, post.likes_count ?? 0) : null;
}

async function unlikePost(postId, userId) {
  const { data: removed, error } = await supabase
    .from("post_likes")
    .delete()
    .eq("post_id", postId)
    .eq("user_id", userId)
    .select("id");
  if (error) throw error;
  return Boolean(removed && removed.length > 0);
}

async function insertLike(postId, userId) {
  const { error: insErr } = await supabase
    .from("post_likes")
    .insert({ post_id: postId, user_id: userId });
  if (insErr) {
    if (isFkViolation(insErr)) return { status: 404 };
    if (isUniqueViolation(insErr)) {
      const likesCount = await fetchPostLikesCount(postId);
      if (likesCount === null) return { status: 404 };
      return { status: 200, body: { liked: true, likes_count: likesCount } };
    }
    throw insErr;
  }

  const [{ data: post, error: postErr }, { data: actorProfile }] = await Promise.all([
    supabase.from("posts").select("user_id, likes_count").eq("id", postId).maybeSingle(),
    supabase.from("user_profiles").select("full_name").eq("user_id", userId).maybeSingle(),
  ]);
  if (postErr) throw postErr;
  if (post) {
    const actorName = actorProfile?.full_name || "Seseorang";
    await createNotification({
      userId: post.user_id,
      actorId: userId,
      type: "like",
      title: `${actorName} menyukai postinganmu`,
      referenceId: postId,
    });
  }
  return { status: 200, body: { liked: true, likes_count: Math.max(0, post?.likes_count ?? 0) } };
}

// -- GET /api/posts - Feed -------------------------------------------------
router.get("/", async (req, res, next) => {
  try {
    const viewerId = resolveOptionalViewerId(req, res);
    if (viewerId === undefined) return;

    const { page, limit, offset, to } = parsePagination(req.query);
    const userId = typeof req.query.user_id === "string" ? req.query.user_id.trim() : "";
    if (userId && !isUuid(userId)) {
      return res.status(400).json({ error: "user_id tidak valid" });
    }

    let query = supabase
      .from("posts")
      .select(`
        id, content, image_url, likes_count, comments_count, created_at,
        user:user_id(id, user_profiles(full_name, initials, avatar_url, prodi, angkatan))
      `, { count: "exact" });

    if (userId) {
      query = query.eq("user_id", userId);
    }

    const { data, count, error } = await query
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .range(offset, to);

    if (error) throw error;

    const posts = data || [];
    let likedIds = new Set();
    if (viewerId && posts.length > 0) {
      const { data: likes, error: likesErr } = await supabase
        .from("post_likes")
        .select("post_id")
        .eq("user_id", viewerId)
        .in("post_id", posts.map((p) => p.id));
      if (likesErr) throw likesErr;
      likedIds = new Set((likes || []).map((l) => l.post_id));
    }

    res.json({
      data: posts.map((p) => ({ ...p, is_liked: likedIds.has(p.id) })),
      total: count,
      page,
      limit,
    });
  } catch (err) {
    next(err);
  }
});

// -- GET /api/posts/leaderboard (defined before /:id routes) ---------------
router.get("/leaderboard", async (req, res, next) => {
  try {
    const { limit } = parsePagination(req.query, { defaultLimit: 10, maxLimit: 50 });
    const { data, error } = await supabase
      .from("user_profiles")
      .select("user_id, full_name, initials, avatar_url, prodi, angkatan, points")
      .order("points", { ascending: false })
      .limit(limit);
    if (error) throw error;
    res.json({ data: (data || []).map((u, i) => ({ ...u, rank: i + 1 })) });
  } catch (err) {
    next(err);
  }
});

// -- POST /api/posts - Buat post -------------------------------------------
router.post(
  "/",
  requireAuth,
  [
    body("content").isString().withMessage("Konten post wajib diisi")
      .bail().trim().notEmpty().withMessage("Konten post wajib diisi")
      .isLength({ max: MAX_POST_LENGTH }).withMessage(`Konten maksimal ${MAX_POST_LENGTH} karakter`),
    body("image_url").optional({ nullable: true, values: "falsy" })
      .custom(isHttpUrl).withMessage("image_url tidak valid"),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    try {
      const { content, image_url } = req.body;
      const { data, error } = await supabase
        .from("posts")
        .insert({ user_id: req.user.userId, content, image_url: image_url || null })
        .select(`
          id, content, image_url, likes_count, comments_count, created_at,
          user:user_id(id, user_profiles(full_name, initials, avatar_url))
        `)
        .single();
      if (error) throw error;

      // Tambah poin untuk post baru
      await awardPoints(req.user.userId, 10);

      res.status(201).json({ ...data, is_liked: false });
    } catch (err) {
      next(err);
    }
  }
);

// -- PUT /api/posts/:id - Edit post caption --------------------------------
router.put(
  "/:id",
  requireAuth,
  [
    body("content").isString().withMessage("Konten post wajib diisi")
      .bail().trim().notEmpty().withMessage("Konten post wajib diisi")
      .isLength({ max: MAX_POST_LENGTH }).withMessage(`Konten maksimal ${MAX_POST_LENGTH} karakter`),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    try {
      // Ownership enforced atomically in the UPDATE itself (no check-then-act race).
      const { data, error } = await supabase
        .from("posts")
        .update({ content: req.body.content })
        .eq("id", req.params.id)
        .eq("user_id", req.user.userId)
        .select(`
          id, content, image_url, likes_count, comments_count, created_at, updated_at,
          user:user_id(id, user_profiles(full_name, initials, avatar_url, prodi, angkatan))
        `)
        .maybeSingle();
      if (error) throw error;
      if (!data) return await postMissingOrForbidden(req.params.id, res);
      res.json(data);
    } catch (err) {
      next(err);
    }
  }
);

// -- DELETE /api/posts/:id -------------------------------------------------
router.delete("/:id", requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("posts")
      .delete()
      .eq("id", req.params.id)
      .eq("user_id", req.user.userId)
      .select("id");
    if (error) throw error;
    if (!data || data.length === 0) return await postMissingOrForbidden(req.params.id, res);
    res.json({ message: "Post dihapus" });
  } catch (err) {
    next(err);
  }
});

// -- POST /api/posts/:id/like - Idempotent set ({ liked }) or toggle ---------
router.post("/:id/like", requireAuth, async (req, res, next) => {
  try {
    const postId = req.params.id;
    const userId = req.user.userId;
    const explicitLiked = typeof req.body?.liked === "boolean" ? req.body.liked : null;

    if (explicitLiked === false) {
      await unlikePost(postId, userId);
      const likesCount = await fetchPostLikesCount(postId);
      if (likesCount === null) return res.status(404).json({ error: "Post tidak ditemukan" });
      return res.json({ liked: false, likes_count: likesCount });
    }

    if (explicitLiked === null) {
      const removed = await unlikePost(postId, userId);
      if (removed) {
        const likesCount = await fetchPostLikesCount(postId);
        if (likesCount === null) return res.status(404).json({ error: "Post tidak ditemukan" });
        return res.json({ liked: false, likes_count: likesCount });
      }
    }

    const result = await insertLike(postId, userId);
    if (result.status === 404) return res.status(404).json({ error: "Post tidak ditemukan" });
    return res.json(result.body);
  } catch (err) {
    next(err);
  }
});

// -- GET /api/posts/:id/comments - Get comments -----------------------------
router.get("/:id/comments", async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("post_comments")
      .select(`
        id, parent_id, content, created_at,
        user:user_id(id, user_profiles(full_name, initials, avatar_url))
      `)
      .eq("post_id", req.params.id)
      .order("created_at", { ascending: true })
      .limit(500);

    if (error) throw error;
    res.json({ data });
  } catch (err) {
    next(err);
  }
});

// -- POST /api/posts/:id/comments - Add comment -----------------------------
router.post(
  "/:id/comments",
  requireAuth,
  [
    body("content").isString().withMessage("Komentar tidak boleh kosong")
      .bail().trim().notEmpty().withMessage("Komentar tidak boleh kosong")
      .isLength({ max: MAX_COMMENT_LENGTH }).withMessage(`Komentar maksimal ${MAX_COMMENT_LENGTH} karakter`),
    body("parent_id").optional({ nullable: true, values: "falsy" })
      .custom(isUuid).withMessage("parent_id tidak valid"),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    try {
      const postId = req.params.id;
      const { content, parent_id } = req.body;

      // Validate post + parent in parallel (also gives us owners for notifications).
      const [{ data: post }, parentRes] = await Promise.all([
        supabase.from("posts").select("user_id").eq("id", postId).maybeSingle(),
        parent_id
          ? supabase.from("post_comments").select("user_id, post_id").eq("id", parent_id).maybeSingle()
          : Promise.resolve({ data: null }),
      ]);
      if (!post) return res.status(404).json({ error: "Post tidak ditemukan" });
      const parentComment = parentRes.data;
      if (parent_id && (!parentComment || parentComment.post_id !== postId)) {
        return res.status(400).json({ error: "Komentar induk tidak valid" });
      }

      const { data, error } = await supabase
        .from("post_comments")
        .insert({
          post_id: postId,
          user_id: req.user.userId,
          content,
          parent_id: parent_id || null,
        })
        .select(`
          id, parent_id, content, created_at,
          user:user_id(id, user_profiles(full_name, initials, avatar_url))
        `)
        .single();
      if (error) throw error;

      const actorName = profileName(data?.user) || "Seseorang";
      const tasks = [
        awardPoints(req.user.userId, 2),
        createNotification({
          userId: post.user_id,
          actorId: req.user.userId,
          type: "comment",
          title: `${actorName} mengomentari postinganmu`,
          body: content,
          referenceId: postId,
        }),
      ];
      if (parentComment && parentComment.user_id !== post.user_id) {
        tasks.push(
          createNotification({
            userId: parentComment.user_id,
            actorId: req.user.userId,
            type: "comment",
            title: `${actorName} membalas komentarmu`,
            body: content,
            referenceId: postId,
          })
        );
      }
      await Promise.all(tasks);

      res.status(201).json(data);
    } catch (err) {
      next(err);
    }
  }
);

// -- DELETE /api/posts/:id/comments/:commentId - Delete own comment --------
router.delete("/:id/comments/:commentId", requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("post_comments")
      .delete()
      .eq("id", req.params.commentId)
      .eq("post_id", req.params.id)
      .eq("user_id", req.user.userId)
      .select("id");
    if (error) throw error;
    if (!data || data.length === 0) {
      const { data: comment } = await supabase
        .from("post_comments")
        .select("id")
        .eq("id", req.params.commentId)
        .eq("post_id", req.params.id)
        .maybeSingle();
      if (!comment) return res.status(404).json({ error: "Komentar tidak ditemukan" });
      return res.status(403).json({ error: "Tidak diizinkan" });
    }
    res.json({ message: "Komentar dihapus" });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
