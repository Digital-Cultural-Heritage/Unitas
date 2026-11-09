const fs = require('fs');
let c = fs.readFileSync('src/routes/users.js', 'utf8');

c = c.replace(
  /if \(existing\.status === "pending"\) \{[\s\S]*?return res\.json\(\{ message: "Koneksi diterima", connection: updated \}\);\n      \}/,
  `if (existing.status === "pending") {
        if (existing.requester_id === requesterId) {
          return res.json({ message: "Permintaan sudah dikirim sebelumnya" });
        }
        const { data: updated, error } = await supabase
          .from("alumni_connections")
          .update({ status: "accepted" })
          .eq("id", existing.id)
          .select()
          .single();
        if (error) throw error;
        return res.json({ message: "Koneksi diterima", connection: updated });
      }`
);

// Add endpoints
const requestsAPI = `
// -- GET /api/users/me/requests -------------------------------------------
router.get("/me/requests", requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from("alumni_connections")
      .select(\`
        id, created_at,
        requester:requester_id(id, user_profiles(full_name, avatar_url, prodi, angkatan))
      \`)
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
    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
`;

c = c.replace('module.exports = router;', requestsAPI);

// We need to make sure existing.requester_id is selected in the connect endpoint
c = c.replace('.select("id, status")', '.select("id, status, requester_id")');

fs.writeFileSync('src/routes/users.js', c);
