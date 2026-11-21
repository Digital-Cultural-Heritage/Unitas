const { describe, it, before, after, beforeEach, afterEach, mock } = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const http = require("node:http");
const sharp = require("sharp");

process.env.SUPABASE_URL = process.env.SUPABASE_URL || "https://example.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "test-service-key";
process.env.JWT_SECRET = process.env.JWT_SECRET || "test-jwt-secret-123456";
process.env.REFRESH_TOKEN_SECRET = process.env.REFRESH_TOKEN_SECRET || "test-refresh-secret-123456";

const app = require("../api/index");
const supabase = require("../src/lib/supabase");
const jwtLib = require("../src/lib/jwt");

let server;
let baseUrl;

function request(method, path, body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, baseUrl);
    const isRaw = Buffer.isBuffer(body);
    const payload = body === null ? null : isRaw ? body : JSON.stringify(body);
    const req = http.request(
      url,
      {
        method,
        headers: {
          ...(payload !== null && !isRaw
            ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) }
            : {}),
          ...(isRaw ? { "Content-Length": payload.length } : {}),
          ...headers,
        },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          try {
            resolve({ status: res.statusCode, body: JSON.parse(data) });
          } catch {
            resolve({ status: res.statusCode, body: data });
          }
        });
      }
    );
    req.on("error", reject);
    if (payload !== null) req.write(payload);
    req.end();
  });
}

function multipartUpload(path, token, { field = "file", filename = "img.png", contentType = "image/png", bytes }) {
  const boundary = "----UnitasTestBoundary" + crypto.randomBytes(6).toString("hex");
  const head = Buffer.from(
    `--${boundary}\r\nContent-Disposition: form-data; name="${field}"; filename="${filename}"\r\nContent-Type: ${contentType}\r\n\r\n`
  );
  const tail = Buffer.from(`\r\n--${boundary}--\r\n`);
  const payload = Buffer.concat([head, bytes, tail]);
  return request("POST", path, payload, {
    Authorization: `Bearer ${token}`,
    "Content-Type": `multipart/form-data; boundary=${boundary}`,
  });
}

// Parse a PostgREST `or(...)` expression with `and(...)`, `eq`, `in.(...)`, `ilike`
function evalOrExpr(expr, row) {
  // Split top-level comma-separated clauses (ignoring commas inside parentheses)
  const clauses = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < expr.length; i++) {
    if (expr[i] === "(") depth++;
    else if (expr[i] === ")") depth--;
    else if (expr[i] === "," && depth === 0) {
      clauses.push(expr.slice(start, i));
      start = i + 1;
    }
  }
  clauses.push(expr.slice(start));
  return clauses.some((c) => evalClause(c.trim(), row));
}

function evalClause(clause, row) {
  if (clause.startsWith("and(") && clause.endsWith(")")) {
    const inner = clause.slice(4, -1);
    const parts = [];
    let depth = 0;
    let start = 0;
    for (let i = 0; i < inner.length; i++) {
      if (inner[i] === "(") depth++;
      else if (inner[i] === ")") depth--;
      else if (inner[i] === "," && depth === 0) {
        parts.push(inner.slice(start, i));
        start = i + 1;
      }
    }
    parts.push(inner.slice(start));
    return parts.every((p) => evalClause(p.trim(), row));
  }
  const mEq = clause.match(/^([^.]+)\.eq\.(.+)$/);
  if (mEq) return String(row[mEq[1]]) === mEq[2];
  const mIn = clause.match(/^([^.]+)\.in\.\((.+)\)$/);
  if (mIn) {
    const set = new Set(mIn[2].split(",").map((s) => s.trim()));
    return set.has(String(row[mIn[1]]));
  }
  const mIlike = clause.match(/^([^.]+)\.ilike\.%(.+)%$/);
  if (mIlike) return String(row[mIlike[1]] ?? "").toLowerCase().includes(mIlike[2].toLowerCase());
  return true;
}

function createRoutesMockDb() {
  const tables = {
    users: [],
    user_profiles: [],
    posts: [],
    post_likes: [],
    post_comments: [],
    events: [],
    event_registrations: [],
    jobs: [],
    saved_jobs: [],
    alumni_connections: [],
    messages: [],
    notifications: [],
  };
  const rpcCalls = [];
  const updateOps = [];
  const lastQueries = [];

  function makeBuilder(table) {
    const state = {
      op: "select",
      selectCols: "*",
      head: false,
      payload: null,
      filters: [],
      orders: [],
      rangeFrom: null,
      rangeTo: null,
      limitCount: null,
      singleMode: null,
      returning: false,
    };

    const builder = {
      select(cols = "*", opts = {}) {
        if (state.op === "select") {
          state.selectCols = cols;
          state.countMode = opts.count || null;
          state.head = Boolean(opts.head);
        } else {
          state.returning = true;
        }
        return builder;
      },
      insert(row) {
        state.op = "insert";
        state.payload = row;
        return builder;
      },
      update(patch) {
        state.op = "update";
        state.payload = patch;
        return builder;
      },
      delete() {
        state.op = "delete";
        return builder;
      },
      eq(col, val) {
        state.filters.push((r) => r[col] === val);
        return builder;
      },
      gte(col, val) {
        state.filters.push((r) => String(r[col] ?? "") >= String(val));
        return builder;
      },
      in(col, vals) {
        const set = new Set(vals);
        state.filters.push((r) => set.has(r[col]));
        return builder;
      },
      ilike(col, pattern) {
        const needle = pattern.replace(/%/g, "").toLowerCase();
        state.filters.push((r) => String(r[col] ?? "").toLowerCase().includes(needle));
        return builder;
      },
      or(expr) {
        lastQueries.push({ table, or: expr });
        state.filters.push((r) => evalOrExpr(expr, r));
        return builder;
      },
      order(col, { ascending = true } = {}) {
        state.orders.push({ col, ascending });
        return builder;
      },
      range(from, to) {
        state.rangeFrom = from;
        state.rangeTo = to;
        return builder;
      },
      limit(n) {
        state.limitCount = n;
        return builder;
      },
      maybeSingle() {
        state.singleMode = "maybe";
        return builder;
      },
      single() {
        state.singleMode = "single";
        return builder;
      },
      then(resolve, reject) {
        try {
          resolve(execute());
        } catch (err) {
          if (reject) reject(err);
          else throw err;
        }
      },
    };

    const matches = (row) => state.filters.every((fn) => fn(row));

    function hydrate(row) {
      const copy = { ...row };
      const profileFor = (uid) => {
        const p = tables.user_profiles.find((u) => u.user_id === uid);
        return p ? { ...p } : null;
      };
      if (table === "users" && state.selectCols.includes("user_profiles")) {
        copy.user_profiles = profileFor(row.id);
      }
      if (table === "posts" && state.selectCols.includes("user:user_id")) {
        copy.user = { id: row.user_id, user_profiles: profileFor(row.user_id) };
      }
      if (table === "post_comments" && state.selectCols.includes("user:user_id")) {
        copy.user = { id: row.user_id, user_profiles: profileFor(row.user_id) };
      }
      if (table === "saved_jobs" && state.selectCols.includes("job:job_id")) {
        copy.job = tables.jobs.find((j) => j.id === row.job_id) || null;
      }
      if (table === "alumni_connections") {
        if (state.selectCols.includes("requester:requester_id")) {
          copy.requester = { id: row.requester_id, user_profiles: profileFor(row.requester_id) };
        }
        if (state.selectCols.includes("addressee:addressee_id")) {
          copy.addressee = { id: row.addressee_id, user_profiles: profileFor(row.addressee_id) };
        }
      }
      return copy;
    }

    function execute() {
      const rows = tables[table];
      if (!rows) return { data: null, error: { message: `Unknown table ${table}` } };

      if (state.op === "insert") {
        const item = {
          id: crypto.randomUUID(),
          created_at: new Date().toISOString(),
          ...state.payload,
        };
        // FK + unique checks for key tables
        if (table === "post_likes") {
          if (!tables.posts.some((p) => p.id === item.post_id)) {
            return { data: null, error: { code: "23503", message: "fk post" } };
          }
          if (rows.some((l) => l.post_id === item.post_id && l.user_id === item.user_id)) {
            return { data: null, error: { code: "23505", message: "dup like" } };
          }
        }
        if (table === "event_registrations") {
          if (!tables.events.some((e) => e.id === item.event_id)) {
            return { data: null, error: { code: "23503", message: "fk event" } };
          }
          if (rows.some((r) => r.event_id === item.event_id && r.user_id === item.user_id)) {
            return { data: null, error: { code: "23505", message: "dup reg" } };
          }
        }
        if (table === "saved_jobs") {
          if (!tables.jobs.some((j) => j.id === item.job_id)) {
            return { data: null, error: { code: "23503", message: "fk job" } };
          }
          if (rows.some((s) => s.job_id === item.job_id && s.user_id === item.user_id)) {
            return { data: null, error: { code: "23505", message: "dup save" } };
          }
        }
        if (table === "alumni_connections") {
          if (!tables.users.some((u) => u.id === item.addressee_id)) {
            return { data: null, error: { code: "23503", message: "fk user" } };
          }
          item.status = item.status || "pending";
        }
        if (table === "posts") {
          item.likes_count = item.likes_count ?? 0;
          item.comments_count = item.comments_count ?? 0;
        }
        if (table === "jobs") {
          item.is_active = item.is_active ?? true;
        }
        if (table === "messages") {
          item.is_read = item.is_read ?? false;
        }
        rows.push(item);
        const hydrated = hydrate(item);
        if (state.singleMode) return { data: hydrated, error: null };
        return { data: state.returning ? [hydrated] : null, error: null };
      }

      if (state.op === "update") {
        updateOps.push({ table, patch: state.payload });
        const updated = [];
        for (let i = 0; i < rows.length; i++) {
          if (matches(rows[i])) {
            rows[i] = { ...rows[i], ...state.payload };
            updated.push(hydrate(rows[i]));
          }
        }
        if (state.singleMode === "maybe") return { data: updated[0] || null, error: null };
        if (state.singleMode === "single") {
          return updated[0]
            ? { data: updated[0], error: null }
            : { data: null, error: { code: "PGRST116", message: "not found" } };
        }
        return { data: state.returning ? updated : null, error: null };
      }

      if (state.op === "delete") {
        const deleted = rows.filter(matches);
        tables[table] = rows.filter((r) => !matches(r));
        return { data: state.returning ? deleted : null, error: null };
      }

      let found = rows.filter(matches).map(hydrate);
      const total = found.length;
      if (state.orders.length > 0) {
        found.sort((a, b) => {
          for (const { col, ascending } of state.orders) {
            if (a[col] === b[col]) continue;
            return (a[col] > b[col] ? 1 : -1) * (ascending ? 1 : -1);
          }
          return 0;
        });
      }
      if (state.rangeFrom !== null && state.rangeTo !== null) {
        found = found.slice(state.rangeFrom, state.rangeTo + 1);
      } else if (state.limitCount !== null) {
        found = found.slice(0, state.limitCount);
      }
      if (state.head) return { data: null, count: total, error: null };
      if (state.singleMode === "maybe") return { data: found[0] || null, error: null };
      if (state.singleMode === "single") {
        return found[0]
          ? { data: found[0], error: null }
          : { data: null, error: { code: "PGRST116", message: "not found" } };
      }
      return { data: found, count: state.countMode ? total : undefined, error: null };
    }

    return builder;
  }

  return {
    tables,
    rpcCalls,
    updateOps,
    lastQueries,
    from: (table) => makeBuilder(table),
    rpc: async (fn, args) => {
      rpcCalls.push({ fn, args });
      return { data: null, error: null };
    },
  };
}

describe("Unitas API Routes (posts, events, jobs, messages, notifications, users, stats, upload)", () => {
  let db;
  const userA = "11111111-1111-4111-8111-111111111111";
  const userB = "22222222-2222-4222-8222-222222222222";
  const userC = "33333333-3333-4333-8333-333333333333";
  const missingId = "99999999-9999-4999-8999-999999999999";
  let tokenA;
  let tokenB;
  let tokenC;

  before((_, done) => {
    tokenA = jwtLib.signAccessToken({ userId: userA, email: "a@unitas.id", role: "alumni" });
    tokenB = jwtLib.signAccessToken({ userId: userB, email: "b@unitas.id", role: "alumni" });
    tokenC = jwtLib.signAccessToken({ userId: userC, email: "c@unitas.id", role: "alumni" });
    server = app.listen(0, () => {
      const { port } = server.address();
      baseUrl = `http://127.0.0.1:${port}`;
      done();
    });
  });

  after((_, done) => {
    server.close(done);
  });

  beforeEach(() => {
    db = createRoutesMockDb();
    db.tables.users.push(
      { id: userA, email: "a@unitas.id", role: "alumni" },
      { id: userB, email: "b@unitas.id", role: "alumni" },
      { id: userC, email: "c@unitas.id", role: "alumni" }
    );
    db.tables.user_profiles.push(
      { id: crypto.randomUUID(), user_id: userA, full_name: "Alice", initials: "AL", points: 100, kota: "Jakarta", prodi: "TI", angkatan: "2020" },
      { id: crypto.randomUUID(), user_id: userB, full_name: "Bob", initials: "BO", points: 50, kota: "Bandung", prodi: "SI", angkatan: "2021" },
      { id: crypto.randomUUID(), user_id: userC, full_name: "Charlie", initials: "CH", points: 10, kota: "Surabaya", prodi: "TI", angkatan: "2022" }
    );
    mock.method(supabase, "from", (t) => db.from(t));
    mock.method(supabase, "rpc", (fn, args) => db.rpc(fn, args));
  });

  afterEach(() => {
    mock.restoreAll();
  });

  it("rejects malformed UUID params with 404 across routes instead of Postgres 500", async () => {
    const resList = await Promise.all([
      request("PUT", "/api/posts/not-a-uuid", { content: "hi" }, { Authorization: `Bearer ${tokenA}` }),
      request("DELETE", "/api/posts/not-a-uuid", null, { Authorization: `Bearer ${tokenA}` }),
      request("POST", "/api/posts/not-a-uuid/like", {}, { Authorization: `Bearer ${tokenA}` }),
      request("GET", "/api/events/not-a-uuid"),
      request("GET", "/api/jobs/not-a-uuid"),
      request("GET", "/api/users/not-a-uuid"),
      request("PUT", "/api/users/requests/not-a-uuid", { action: "accept" }, { Authorization: `Bearer ${tokenA}` }),
      request("PUT", "/api/notifications/not-a-uuid/read", {}, { Authorization: `Bearer ${tokenA}` }),
      request("GET", "/api/messages/not-a-uuid", null, { Authorization: `Bearer ${tokenA}` }),
    ]);
    for (const r of resList) {
      assert.equal(r.status, 404);
    }
  });

  it("posts: validation, ownership (403/404), atomic like toggle, comments & leaderboard", async () => {
    // Reject blank content and non-http image_url
    assert.equal(
      (await request("POST", "/api/posts", { content: "   " }, { Authorization: `Bearer ${tokenA}` })).status,
      400
    );
    assert.equal(
      (
        await request(
          "POST",
          "/api/posts",
          { content: "Valid", image_url: "javascript:alert(1)" },
          { Authorization: `Bearer ${tokenA}` }
        )
      ).status,
      400
    );

    // Create post
    const created = await request(
      "POST",
      "/api/posts",
      { content: "  Halo Unitas!  ", image_url: "https://cdn.example.com/a.webp" },
      { Authorization: `Bearer ${tokenA}` }
    );
    assert.equal(created.status, 201);
    assert.equal(created.body.content, "Halo Unitas!");
    assert.equal(db.rpcCalls.length, 1);
    const postId = created.body.id;

    // Clamped pagination
    const feed = await request("GET", "/api/posts?page=-5&limit=9999");
    assert.equal(feed.status, 200);
    assert.equal(feed.body.page, 1);
    assert.equal(feed.body.limit, 50);

    // Leaderboard
    const lb = await request("GET", "/api/posts/leaderboard?limit=2");
    assert.equal(lb.status, 200);
    assert.equal(lb.body.data.length, 2);
    assert.equal(lb.body.data[0].rank, 1);
    assert.equal(lb.body.data[0].full_name, "Alice");

    // Non-owner edit/delete -> 403, missing -> 404
    assert.equal(
      (await request("PUT", `/api/posts/${postId}`, { content: "Hack" }, { Authorization: `Bearer ${tokenB}` })).status,
      403
    );
    assert.equal(
      (await request("PUT", `/api/posts/${missingId}`, { content: "X" }, { Authorization: `Bearer ${tokenA}` })).status,
      404
    );
    assert.equal(
      (await request("DELETE", `/api/posts/${postId}`, null, { Authorization: `Bearer ${tokenB}` })).status,
      403
    );

    // Toggle like on/off and 404 on missing post
    assert.equal((await request("POST", `/api/posts/${missingId}/like`, {}, { Authorization: `Bearer ${tokenB}` })).status, 404);
    const likeOn = await request("POST", `/api/posts/${postId}/like`, {}, { Authorization: `Bearer ${tokenB}` });
    assert.equal(likeOn.status, 200);
    assert.equal(likeOn.body.liked, true);
    assert.equal(db.tables.notifications.length, 1);
    const likeOff = await request("POST", `/api/posts/${postId}/like`, {}, { Authorization: `Bearer ${tokenB}` });
    assert.equal(likeOff.status, 200);
    assert.equal(likeOff.body.liked, false);

    // Comments + cross-post parent validation
    const otherPost = await request("POST", "/api/posts", { content: "Post 2" }, { Authorization: `Bearer ${tokenA}` });
    const c1 = await request(
      "POST",
      `/api/posts/${postId}/comments`,
      { content: "Komentar 1" },
      { Authorization: `Bearer ${tokenB}` }
    );
    assert.equal(c1.status, 201);
    const badReply = await request(
      "POST",
      `/api/posts/${otherPost.body.id}/comments`,
      { content: "Cross post reply", parent_id: c1.body.id },
      { Authorization: `Bearer ${tokenA}` }
    );
    assert.equal(badReply.status, 400);

    // Comment owner delete
    assert.equal(
      (await request("DELETE", `/api/posts/${postId}/comments/${c1.body.id}`, null, { Authorization: `Bearer ${tokenA}` })).status,
      403
    );
    assert.equal(
      (await request("DELETE", `/api/posts/${postId}/comments/${c1.body.id}`, null, { Authorization: `Bearer ${tokenB}` })).status,
      200
    );
  });

  it("events: validates dates/urls, enforces creator ownership, and handles registration races", async () => {
    // Reject invalid calendar date
    assert.equal(
      (
        await request(
          "POST",
          "/api/events",
          { title: "Reuni", category: "Reuni", event_date: "2027-02-30", location: "Aula" },
          { Authorization: `Bearer ${tokenA}` }
        )
      ).status,
      400
    );

    const ev = await request(
      "POST",
      "/api/events",
      {
        title: "Seminar Alumni",
        category: "Seminar",
        event_date: "2099-05-10",
        start_time: "09:00",
        location: "Jakarta",
        is_online: false,
      },
      { Authorization: `Bearer ${tokenA}` }
    );
    assert.equal(ev.status, 201);
    const evId = ev.body.id;

    // Empty PUT rejected, non-owner -> 403
    assert.equal((await request("PUT", `/api/events/${evId}`, {}, { Authorization: `Bearer ${tokenA}` })).status, 400);
    assert.equal(
      (await request("PUT", `/api/events/${evId}`, { title: "Hijack" }, { Authorization: `Bearer ${tokenB}` })).status,
      403
    );

    // Registration: 201 then 409 duplicate, 404 missing event
    assert.equal(
      (await request("POST", `/api/events/${missingId}/register`, {}, { Authorization: `Bearer ${tokenB}` })).status,
      404
    );
    assert.equal(
      (await request("POST", `/api/events/${evId}/register`, {}, { Authorization: `Bearer ${tokenB}` })).status,
      201
    );
    assert.equal(
      (await request("POST", `/api/events/${evId}/register`, {}, { Authorization: `Bearer ${tokenB}` })).status,
      409
    );
    assert.equal(
      (await request("DELETE", `/api/events/${evId}/register`, null, { Authorization: `Bearer ${tokenB}` })).status,
      200
    );
  });

  it("jobs: sanitizes search, validates salaries/urls/emails, preserves 0 salary, atomic save", async () => {
    const badSalary = await request(
      "POST",
      "/api/jobs",
      { title: "Dev", company: "PT A", location: "Remote", salary_min: 100, salary_max: 50 },
      { Authorization: `Bearer ${tokenA}` }
    );
    assert.equal(badSalary.status, 400);

    const badEmail = await request(
      "POST",
      "/api/jobs",
      { title: "Dev", company: "PT A", location: "Remote", contact_email: "not-an-email" },
      { Authorization: `Bearer ${tokenA}` }
    );
    assert.equal(badEmail.status, 400);

    const created = await request(
      "POST",
      "/api/jobs",
      {
        title: "Backend Dev",
        company: "Unitas Tech",
        location: "Remote",
        salary_min: 0,
        salary_max: 10000000,
        tags: ["Node.js", "SQL"],
        apply_url: "https://unitas.id/apply",
        contact_email: "hr@unitas.id",
        is_remote: true,
      },
      { Authorization: `Bearer ${tokenA}` }
    );
    assert.equal(created.status, 201);
    assert.equal(created.body.salary_min, 0);
    const jobId = created.body.id;

    // PostgREST injection characters stripped from search query
    await request("GET", "/api/jobs?q=" + encodeURIComponent("dev,id.eq.1)"));
    const qLog = db.lastQueries.find((x) => x.table === "jobs");
    assert.ok(qLog && !qLog.or.includes("id.eq.1)"));

    // Non-owner cannot close or delete
    assert.equal(
      (await request("PUT", `/api/jobs/${jobId}`, { is_active: false }, { Authorization: `Bearer ${tokenB}` })).status,
      403
    );
    assert.equal(
      (await request("PUT", `/api/jobs/${jobId}`, { is_active: false, apply_url: null }, { Authorization: `Bearer ${tokenA}` })).status,
      200
    );

    // Save non-existent job -> 404, valid -> toggle true/false
    assert.equal((await request("POST", `/api/jobs/${missingId}/save`, {}, { Authorization: `Bearer ${tokenB}` })).status, 404);
    assert.equal((await request("POST", `/api/jobs/${jobId}/save`, {}, { Authorization: `Bearer ${tokenB}` })).body.saved, true);
    assert.equal((await request("POST", `/api/jobs/${jobId}/save`, {}, { Authorization: `Bearer ${tokenB}` })).body.saved, false);
  });

  it("messages: enforces connection check, returns newest 100 chronologically, skips read-update when clean", async () => {
    // Cannot message self or unconnected user
    assert.equal(
      (await request("GET", `/api/messages/${userA}`, null, { Authorization: `Bearer ${tokenA}` })).status,
      400
    );
    assert.equal(
      (await request("GET", `/api/messages/${userB}`, null, { Authorization: `Bearer ${tokenA}` })).status,
      403
    );
    assert.equal(
      (await request("POST", `/api/messages/${userB}`, { content: "Hi" }, { Authorization: `Bearer ${tokenA}` })).status,
      403
    );

    // Conversations empty when no connections
    const emptyConvs = await request("GET", "/api/messages/conversations", null, {
      Authorization: `Bearer ${tokenA}`,
    });
    assert.equal(emptyConvs.status, 200);
    assert.deepEqual(emptyConvs.body, { data: [], total_unread: 0 });

    // Connect A <-> B
    db.tables.alumni_connections.push({
      id: crypto.randomUUID(),
      requester_id: userA,
      addressee_id: userB,
      status: "accepted",
      created_at: new Date().toISOString(),
    });

    // Seed 120 messages so we verify newest 100 are returned in chronological order
    const baseMs = Date.now() - 200_000;
    for (let i = 1; i <= 120; i++) {
      db.tables.messages.push({
        id: crypto.randomUUID(),
        sender_id: userB,
        receiver_id: userA,
        content: `msg-${i}`,
        is_read: i <= 118, // 2 unread (119, 120)
        created_at: new Date(baseMs + i * 1000).toISOString(),
      });
    }

    const convs = await request("GET", "/api/messages/conversations", null, { Authorization: `Bearer ${tokenA}` });
    assert.equal(convs.status, 200);
    assert.equal(convs.body.total_unread, 2);
    assert.equal(convs.body.data[0].last_message, "msg-120");
    assert.equal(convs.body.data[0].unread_count, 2);

    // First GET fetches newest 100 (msg-21..msg-120) and marks unread as read (1 UPDATE)
    const thread = await request("GET", `/api/messages/${userB}`, null, { Authorization: `Bearer ${tokenA}` });
    assert.equal(thread.status, 200);
    assert.equal(thread.body.data.length, 100);
    assert.equal(thread.body.data[0].content, "msg-21");
    assert.equal(thread.body.data[99].content, "msg-120");
    assert.equal(db.updateOps.filter((u) => u.table === "messages").length, 1);

    // Second GET (polling) skips UPDATE because no unread messages remain
    await request("GET", `/api/messages/${userB}`, null, { Authorization: `Bearer ${tokenA}` });
    assert.equal(db.updateOps.filter((u) => u.table === "messages").length, 1);

    // Send message
    const sent = await request(
      "POST",
      `/api/messages/${userB}`,
      { content: "  Halo Bob  " },
      { Authorization: `Bearer ${tokenA}` }
    );
    assert.equal(sent.status, 201);
    assert.equal(sent.body.content, "Halo Bob");
  });

  it("users & notifications: validates profile updates, connect flow, request action, and notif IDOR", async () => {
    // GET /me preserves users.id (must not be overwritten by user_profiles.id)
    const meRes = await request("GET", "/api/users/me", null, { Authorization: `Bearer ${tokenA}` });
    assert.equal(meRes.status, 200);
    assert.equal(meRes.body.id, userA);
    assert.equal(meRes.body.user_id, userA);
    assert.equal(meRes.body.email, "a@unitas.id");

    // PUT /me rejects empty full_name and javascript: linkedin, accepts empty optional fields
    assert.equal(
      (await request("PUT", "/api/users/me", { full_name: "  " }, { Authorization: `Bearer ${tokenA}` })).status,
      400
    );
    assert.equal(
      (await request("PUT", "/api/users/me", { linkedin: "javascript:alert(1)" }, { Authorization: `Bearer ${tokenA}` })).status,
      400
    );
    const updatedMe = await request(
      "PUT",
      "/api/users/me",
      { full_name: "Alice Updated", bio: "", linkedin: "" },
      { Authorization: `Bearer ${tokenA}` }
    );
    assert.equal(updatedMe.status, 200);
    assert.equal(updatedMe.body.full_name, "Alice Updated");
    assert.equal(updatedMe.body.linkedin, null);

    // Connect missing user -> 404
    assert.equal(
      (await request("POST", `/api/users/${missingId}/connect`, {}, { Authorization: `Bearer ${tokenA}` })).status,
      404
    );

    // A -> B connect request -> creates notification for B
    const reqConn = await request("POST", `/api/users/${userB}/connect`, {}, { Authorization: `Bearer ${tokenA}` });
    assert.equal(reqConn.status, 201);
    const connId = reqConn.body.connection.id;

    // Directory shows pending for A, incoming for B
    const dirA = await request("GET", "/api/users", null, { Authorization: `Bearer ${tokenA}` });
    const dirB = await request("GET", "/api/users", null, { Authorization: `Bearer ${tokenB}` });
    assert.equal(dirA.body.data.find((u) => u.user_id === userB).connection_status, "pending");
    assert.equal(dirB.body.data.find((u) => u.user_id === userA).connection_status, "incoming");

    // Notifications IDOR: A cannot mark B's notification read
    const notifForB = db.tables.notifications[0];
    assert.equal(
      (await request("PUT", `/api/notifications/${notifForB.id}/read`, {}, { Authorization: `Bearer ${tokenA}` })).status,
      404
    );
    assert.equal(
      (await request("PUT", `/api/notifications/${notifForB.id}/read`, {}, { Authorization: `Bearer ${tokenB}` })).status,
      200
    );

    // PUT /requests/:id rejects invalid action, rejects non-addressee, accepts valid action once
    assert.equal(
      (await request("PUT", `/api/users/requests/${connId}`, { action: "invalid" }, { Authorization: `Bearer ${tokenB}` })).status,
      400
    );
    assert.equal(
      (await request("PUT", `/api/users/requests/${connId}`, { action: "accept" }, { Authorization: `Bearer ${tokenA}` })).status,
      404
    );
    assert.equal(
      (await request("PUT", `/api/users/requests/${connId}`, { action: "accept" }, { Authorization: `Bearer ${tokenB}` })).status,
      200
    );
    // Replaying accept returns 409
    assert.equal(
      (await request("PUT", `/api/users/requests/${connId}`, { action: "reject" }, { Authorization: `Bearer ${tokenB}` })).status,
      409
    );
  });

  it("DELETE /api/users/me rejects logged-out tokens with 401, deletes active user, and returns 404 after", async () => {
    const loggedOutRes = await request("DELETE", "/api/users/me", null, {
      Authorization: `Bearer ${tokenC}`,
    });
    assert.equal(loggedOutRes.status, 401);
    assert.ok(db.tables.users.some((u) => u.id === userC));

    db.tables.users.find((u) => u.id === userC).refresh_token = "active-rt";
    const okRes = await request("DELETE", "/api/users/me", null, {
      Authorization: `Bearer ${tokenC}`,
    });
    assert.equal(okRes.status, 200);
    assert.equal(db.tables.users.some((u) => u.id === userC), false);

    const missingRes = await request("DELETE", "/api/users/me", null, {
      Authorization: `Bearer ${tokenC}`,
    });
    assert.equal(missingRes.status, 404);
  });

  it("stats returns counts and propagates DB errors as 500", async () => {
    const ok = await request("GET", "/api/stats");
    assert.equal(ok.status, 200);
    assert.equal(ok.body.total_alumni, 3);

    mock.restoreAll();
    mock.method(supabase, "from", () => ({
      select: () => ({
        gte: () => Promise.resolve({ count: null, error: new Error("db down") }),
        eq: () => Promise.resolve({ count: null, error: new Error("db down") }),
        then: (r) => r({ count: null, error: new Error("db down") }),
      }),
    }));
    const errRes = await request("GET", "/api/stats");
    assert.equal(errRes.status, 500);
  });

  it("upload validates mimetype, rejects fake/corrupt images with 400, and processes valid PNG to WebP", async () => {
    // Missing file -> 400
    const noFile = await request("POST", "/api/upload/post", {}, { Authorization: `Bearer ${tokenA}` });
    assert.equal(noFile.status, 400);

    // Disallowed mimetype -> 400 (not 500)
    const badMime = await multipartUpload("/api/upload/post", tokenA, {
      filename: "evil.svg",
      contentType: "image/svg+xml",
      bytes: Buffer.from("<svg></svg>"),
    });
    assert.equal(badMime.status, 400);

    // Spoofed PNG header with non-image bytes -> 400 (not 500)
    const fakePng = await multipartUpload("/api/upload/post", tokenA, {
      filename: "fake.png",
      contentType: "image/png",
      bytes: Buffer.from("not actually a png"),
    });
    assert.equal(fakePng.status, 400);

    // Valid 2x2 PNG -> processed to WebP and uploaded to mocked storage
    const validPng = await sharp({
      create: { width: 2, height: 2, channels: 3, background: { r: 30, g: 58, b: 95 } },
    })
      .png()
      .toBuffer();

    let uploadedArgs;
    mock.method(supabase.storage, "from", (bucket) => ({
      upload: async (name, buf, opts) => {
        uploadedArgs = { bucket, name, len: buf.length, opts };
        return { error: null };
      },
      getPublicUrl: (name) => ({ data: { publicUrl: `https://cdn.example.com/${bucket}/${name}` } }),
    }));

    const okPost = await multipartUpload("/api/upload/post", tokenA, {
      filename: "photo.png",
      contentType: "image/png",
      bytes: validPng,
    });
    assert.equal(okPost.status, 200);
    assert.equal(uploadedArgs.bucket, "post-images");
    assert.equal(uploadedArgs.opts.contentType, "image/webp");
    assert.ok(okPost.body.url.endsWith(".webp"));

    const okAvatar = await multipartUpload("/api/upload/avatar", tokenA, {
      filename: "avatar.png",
      contentType: "image/png",
      bytes: validPng,
    });
    assert.equal(okAvatar.status, 200);
    assert.ok(okAvatar.body.url.includes(`${userA}.webp?v=`));
    assert.equal(db.tables.user_profiles.find((p) => p.user_id === userA).avatar_url, okAvatar.body.url);
  });
});
