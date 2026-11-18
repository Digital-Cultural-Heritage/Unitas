const express = require("express");
const { body, validationResult } = require("express-validator");
const supabase = require("../lib/supabase");
const { requireAuth } = require("../middleware/auth");
const { createNotification } = require("../lib/notifications");

const router = express.Router();

// -- GET /api/posts — Feed -------------------------------------------------
router.get("/", async (req, res, next) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const offset = (Number(page) - 1) * Number(limit);

    const { data, count, error } = await supabase
      .from("posts")
      .select(`
        id, content, image_url, likes_count, comments_count, created_at,
        user:user_id(id, user_profiles(full_name, initials, avatar_url, prodi, angkatan))
      `, { count: "exact" })
      .order("created_at", { ascending: false })
      .range(offset, offset + Number(limit) - 1);

    if (error) throw error;
    res.json({ data, total: count, page: Number(page), limit: Number(limit) });
  } catch (err) {
    next(err);
  }
});

// -- POST /api/posts — Buat post -------------------------------------------
router.post(
  "/",
  requireAuth,
  [body("content").notEmpty().withMessage("Konten post wajib diisi")],
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
      await supabase.rpc("increment_points", { uid: req.user.userId, pts: 10 });

      res.status(201).json(data);
    } catch (err) {
      next(err);
    }
  }
);

// -- PUT /api/posts/:id — Edit post caption --------------------------------
router.put(
  "/:id",
  requireAuth,
  [body("content").trim().notEmpty().withMessage("Konten post wajib diisi")],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    try {
      const { data: post, error: fetchErr } = await supabase
        .from("posts")
        .select("user_id")
        .eq("id", req.params.id)
        .single();
      if (fetchErr || !post) return res.status(404).json({ error: "Post tidak ditemukan" });
      if (post.user_id !== req.user.userId) return res.status(403).json({ error: "Tidak diizinkan" });

      const { data, error } = await supabase
        .from("posts")
        .update({ content: req.body.content.trim() })
        .eq("id", req.params.id)
        .select(`
          id, content, image_url, likes_count, comments_count, created_at, updated_at,
          user:user_id(id, user_profiles(full_name, initials, avatar_url, prodi, angkatan))
        `)
        .single();
      if (error) throw error;
      res.json(data);
    } catch (err) {
      next(err);
    }
  }
);

// -- DELETE /api/posts/:id -------------------------------------------------
router.delete("/:id", requireAuth, async (req, res, next) => {
  try {
    const { data: post, error: fetchErr } = await supabase
      .from("posts")
      .select("user_id")
      .eq("id", req.params.id)
      .single();
    if (fetchErr || !post) return res.status(404).json({ error: "Post tidak ditemukan" });
    if (post.user_id !== req.user.userId) return res.status(403).json({ error: "Tidak diizinkan" });

    const { error } = await supabase.from("posts").delete().eq("id", req.params.id);
    if (error) throw error;
    res.json({ message: "Post dihapus" });
  } catch (err) {
    next(err);
  }
});

// -- POST /api/posts/:id/like — Toggle like --------------------------------
router.post("/:id/like", requireAuth, async (req, res, next) => {
  try {
    const postId = req.params.id;
    const userId = req.user.userId;

    const { data: existing } = await supabase
      .from("post_likes")
      .select("id")
      .eq("post_id", postId)
      .eq("user_id", userId)
      .single();

    if (existing) {
      // Unlike
      await supabase.from("post_likes").delete().eq("id", existing.id);
      res.json({ liked: false });
    } else {
      // Like
      await supabase.from("post_likes").insert({ post_id: postId, user_id: userId });

      const [{ data: post }, { data: actorProfile }] = await Promise.all([
        supabase.from("posts").select("user_id").eq("id", postId).single(),
        supabase.from("user_profiles").select("full_name").eq("user_id", userId).single(),
      ]);
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

      res.json({ liked: true });
    }
  } catch (err) {
    next(err);
  }
});

// -- GET /api/posts/leaderboard --------------------------------------------
router.get("/leaderboard", async (req, res, next) => {
  try {
    const { limit = 10 } = req.query;
    const { data, error } = await supabase
      .from("user_profiles")
      .select("user_id, full_name, initials, avatar_url, prodi, angkatan, points")
      .order("points", { ascending: false })
      .limit(Number(limit));
    if (error) throw error;
    res.json({ data: data.map((u, i) => ({ ...u, rank: i + 1 })) });
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
      .order("created_at", { ascending: true });
    
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
  [body("content").notEmpty().withMessage("Komentar tidak boleh kosong")],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    
    try {
      const postId = req.params.id;
      const { content, parent_id } = req.body;
      
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
      
      await supabase.rpc("increment_points", { uid: req.user.userId, pts: 2 });

      const actorName = data?.user?.user_profiles?.[0]?.full_name || "Seseorang";
      const { data: post } = await supabase
        .from("posts")
        .select("user_id")
        .eq("id", postId)
        .single();
      if (post) {
        await createNotification({
          userId: post.user_id,
          actorId: req.user.userId,
          type: "comment",
          title: `${actorName} mengomentari postinganmu`,
          body: content,
          referenceId: postId,
        });
      }

      if (parent_id) {
        const { data: parentComment } = await supabase
          .from("post_comments")
          .select("user_id")
          .eq("id", parent_id)
          .single();
        if (parentComment && parentComment.user_id !== post?.user_id) {
          await createNotification({
            userId: parentComment.user_id,
            actorId: req.user.userId,
            type: "comment",
            title: `${actorName} membalas komentarmu`,
            body: content,
            referenceId: postId,
          });
        }
      }
      
      res.status(201).json(data);
    } catch (err) {
      next(err);
    }
  }
);

// -- DELETE /api/posts/:id/comments/:commentId - Delete own comment --------
router.delete("/:id/comments/:commentId", requireAuth, async (req, res, next) => {
  try {
    const { data: comment, error: fetchErr } = await supabase
      .from("post_comments")
      .select("user_id")
      .eq("id", req.params.commentId)
      .eq("post_id", req.params.id)
      .single();
    if (fetchErr || !comment) return res.status(404).json({ error: "Komentar tidak ditemukan" });
    if (comment.user_id !== req.user.userId) return res.status(403).json({ error: "Tidak diizinkan" });

    const { error } = await supabase
      .from("post_comments")
      .delete()
      .eq("id", req.params.commentId);
    if (error) throw error;
    res.json({ message: "Komentar dihapus" });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
