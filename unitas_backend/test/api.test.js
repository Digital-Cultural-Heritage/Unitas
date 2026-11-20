const { describe, it, before, after, beforeEach, afterEach, mock } = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const http = require("node:http");

// Ensure required env vars exist for module initialization in test
process.env.SUPABASE_URL = process.env.SUPABASE_URL || "https://example.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "test-service-key";
process.env.JWT_SECRET = process.env.JWT_SECRET || "test-jwt-secret-123456";
process.env.REFRESH_TOKEN_SECRET = process.env.REFRESH_TOKEN_SECRET || "test-refresh-secret-123456";
process.env.BCRYPT_ROUNDS = process.env.BCRYPT_ROUNDS || "4";

const app = require("../api/index");
const supabase = require("../src/lib/supabase");
const jwtLib = require("../src/lib/jwt");

let server;
let baseUrl;

function request(method, path, body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, baseUrl);
    const payload = body === null ? null : typeof body === "string" ? body : JSON.stringify(body);
    const req = http.request(
      url,
      {
        method,
        headers: {
          ...(payload !== null
            ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) }
            : {}),
          ...headers,
        },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          try {
            resolve({ status: res.statusCode, headers: res.headers, body: JSON.parse(data) });
          } catch {
            resolve({ status: res.statusCode, headers: res.headers, body: data });
          }
        });
      }
    );
    req.on("error", reject);
    if (payload !== null) req.write(payload);
    req.end();
  });
}

// Lightweight in-memory Supabase query mock for deterministic auth flow tests
function createMockDb() {
  const tables = {
    users: [],
    user_profiles: [],
    password_reset_otps: [],
  };

  function makeBuilder(table) {
    const state = {
      op: "select",
      selectCols: "*",
      payload: null,
      filters: [],
      orderBy: null,
      limitCount: null,
      singleMode: null,
      returning: false,
    };

    const builder = {
      select(cols = "*") {
        if (state.op === "select") state.selectCols = cols;
        else state.returning = true;
        return builder;
      },
      insert(row) {
        state.op = "insert";
        state.payload = row;
        return builder;
      },
      upsert(row, opts = {}) {
        state.op = "upsert";
        state.payload = row;
        state.onConflict = opts.onConflict || "id";
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
      order(col, { ascending = true } = {}) {
        state.orderBy = { col, ascending };
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

    function matches(row) {
      return state.filters.every((fn) => fn(row));
    }

    function hydrate(row) {
      const copy = { ...row };
      if (table === "users" && state.selectCols.includes("user_profiles")) {
        const prof = tables.user_profiles.find((p) => p.user_id === row.id) || null;
        copy.user_profiles = prof ? { ...prof } : null;
      }
      return copy;
    }

    function execute() {
      const rows = tables[table];
      if (!rows) return { data: null, error: new Error(`Unknown table ${table}`) };

      if (state.op === "insert") {
        const item = { id: crypto.randomUUID(), created_at: new Date().toISOString(), ...state.payload };
        if (table === "users") {
          if (rows.some((u) => u.email === item.email)) {
            return { data: null, error: { code: "23505", message: "duplicate email" } };
          }
          if (item.google_sub && rows.some((u) => u.google_sub === item.google_sub)) {
            return { data: null, error: { code: "23505", message: "duplicate google_sub" } };
          }
        }
        if (table === "password_reset_otps") {
          item.used = item.used ?? false;
          item.attempts = item.attempts ?? 0;
        }
        rows.push(item);
        return { data: state.returning ? [item] : null, error: null };
      }

      if (state.op === "upsert") {
        const key = state.onConflict;
        const idx = rows.findIndex((r) => r[key] === state.payload[key]);
        if (idx >= 0) {
          rows[idx] = { ...rows[idx], ...state.payload };
        } else {
          rows.push({ id: crypto.randomUUID(), ...state.payload });
        }
        return { data: null, error: null };
      }

      if (state.op === "update") {
        const updated = [];
        for (let i = 0; i < rows.length; i++) {
          if (matches(rows[i])) {
            rows[i] = { ...rows[i], ...state.payload };
            updated.push({ ...rows[i] });
          }
        }
        return { data: state.returning ? updated : null, error: null };
      }

      if (state.op === "delete") {
        tables[table] = rows.filter((r) => !matches(r));
        return { data: null, error: null };
      }

      let found = rows.filter(matches).map(hydrate);
      if (state.orderBy) {
        const { col, ascending } = state.orderBy;
        found.sort((a, b) => (a[col] > b[col] ? 1 : a[col] < b[col] ? -1 : 0) * (ascending ? 1 : -1));
      }
      if (state.limitCount !== null) found = found.slice(0, state.limitCount);
      if (state.singleMode === "maybe") return { data: found[0] || null, error: null };
      if (state.singleMode === "single") {
        return found[0]
          ? { data: found[0], error: null }
          : { data: null, error: { code: "PGRST116", message: "not found" } };
      }
      return { data: found, error: null };
    }

    return builder;
  }

  return {
    tables,
    from: (table) => makeBuilder(table),
  };
}

describe("Unitas Backend API", () => {
  before((_, done) => {
    server = app.listen(0, () => {
      const { port } = server.address();
      baseUrl = `http://127.0.0.1:${port}`;
      done();
    });
  });

  after((_, done) => {
    server.close(done);
  });

  it("GET / returns API metadata", async () => {
    const res = await request("GET", "/");
    assert.equal(res.status, 200);
    assert.equal(res.body.name, "Unitas API");
    assert.equal(res.body.status, "running");
  });

  it("GET /api/health returns ok", async () => {
    const res = await request("GET", "/api/health");
    assert.equal(res.status, 200);
    assert.equal(res.body.status, "ok");
  });

  it("GET /api/unknown returns 404", async () => {
    const res = await request("GET", "/api/does-not-exist");
    assert.equal(res.status, 404);
  });

  it("Malformed JSON body returns 400 instead of 500", async () => {
    const res = await request("POST", "/api/auth/login", "{bad-json");
    assert.equal(res.status, 400);
    assert.ok(res.body.error);
  });

  it("CORS headers are set on responses", async () => {
    const res = await request("GET", "/api/health", null, { Origin: "https://example.com" });
    assert.equal(res.status, 200);
    assert.equal(res.headers["access-control-allow-origin"], "*");
  });

  it("Missing required env returns 503 on /api/* without crashing cold start", async () => {
    const origJwt = process.env.JWT_SECRET;
    process.env.JWT_SECRET = "";
    const indexPath = require.resolve("../api/index");
    const cached = require.cache[indexPath];
    delete require.cache[indexPath];
    let degradedServer;
    try {
      const degradedApp = require("../api/index");
      degradedServer = degradedApp.listen(0);
      await new Promise((r) => degradedServer.once("listening", r));
      const port = degradedServer.address().port;

      const health = await new Promise((resolve, reject) => {
        http.get(`http://127.0.0.1:${port}/api/health`, (res) => {
          res.resume();
          res.on("end", () => resolve(res.statusCode));
        }).on("error", reject);
      });
      const auth = await new Promise((resolve, reject) => {
        http.get(`http://127.0.0.1:${port}/api/auth/me`, (res) => {
          res.resume();
          res.on("end", () => resolve(res.statusCode));
        }).on("error", reject);
      });
      assert.equal(health, 200);
      assert.equal(auth, 503);
    } finally {
      if (degradedServer) await new Promise((r) => degradedServer.close(r));
      if (origJwt === undefined) delete process.env.JWT_SECRET;
      else process.env.JWT_SECRET = origJwt;
      if (cached) require.cache[indexPath] = cached;
      else delete require.cache[indexPath];
    }
  });

  it("POST /api/auth/login validates empty body with 400", async () => {
    const res = await request("POST", "/api/auth/login", {});
    assert.equal(res.status, 400);
  });

  it("POST /api/auth/register validates short password and >72-byte password with 400", async () => {
    const shortRes = await request("POST", "/api/auth/register", {
      email: "user@example.com",
      password: "123",
      full_name: "Test User",
      prodi: "Informatika",
      angkatan: "2022",
    });
    assert.equal(shortRes.status, 400);

    const longRes = await request("POST", "/api/auth/register", {
      email: "user@example.com",
      password: "a".repeat(73),
      full_name: "Test User",
      prodi: "Informatika",
      angkatan: "2022",
    });
    assert.equal(longRes.status, 400);
  });

  it("Protected endpoints reject unauthenticated requests with 401", async () => {
    const sampleId = "11111111-1111-4111-8111-111111111111";
    const [meRes, postsRes, notifRes, msgRes, jobsRes, appliedRes, applyRes, applicantsRes, statusRes, cvRes] = await Promise.all([
      request("GET", "/api/auth/me"),
      request("POST", "/api/posts", { content: "Halo" }),
      request("GET", "/api/notifications"),
      request("GET", "/api/messages/conversations"),
      request("GET", "/api/jobs/my-jobs/all"),
      request("GET", "/api/jobs/applied"),
      request("POST", `/api/jobs/${sampleId}/apply`, { cv_url: "https://example.com/cv.pdf" }),
      request("GET", `/api/jobs/${sampleId}/applicants`),
      request("PUT", `/api/jobs/applications/${sampleId}/status`, { status: "reviewed" }),
      request("POST", "/api/upload/cv", {}),
    ]);
    assert.equal(meRes.status, 401);
    assert.equal(postsRes.status, 401);
    assert.equal(notifRes.status, 401);
    assert.equal(msgRes.status, 401);
    assert.equal(jobsRes.status, 401);
    assert.equal(appliedRes.status, 401);
    assert.equal(applyRes.status, 401);
    assert.equal(applicantsRes.status, 401);
    assert.equal(statusRes.status, 401);
    assert.equal(cvRes.status, 401);
  });

  describe("JWT token separation", () => {
    it("rejects refresh token when used as access token and vice versa", async () => {
      const payload = { userId: "u-1", email: "a@b.com", role: "alumni" };
      const access = jwtLib.signAccessToken(payload);
      const refresh = jwtLib.signRefreshToken(payload);

      assert.equal(jwtLib.verifyAccessToken(access).userId, "u-1");
      assert.equal(jwtLib.verifyRefreshToken(refresh).userId, "u-1");
      assert.throws(() => jwtLib.verifyAccessToken(refresh));
      assert.throws(() => jwtLib.verifyRefreshToken(access));

      const res = await request("GET", "/api/auth/me", null, { Authorization: `Bearer ${refresh}` });
      assert.equal(res.status, 401);
    });
  });

  describe("Auth end-to-end flows (mocked DB & Google verifier)", () => {
    let db;
    let googleMock;
    const savedEnv = {};

    beforeEach(() => {
      db = createMockDb();
      mock.method(supabase, "from", (table) => db.from(table));

      const { OAuth2Client } = require("google-auth-library");
      googleMock = mock.method(OAuth2Client.prototype, "verifyIdToken", async () => {
        throw new Error("unexpected verifyIdToken call");
      });

      savedEnv.GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
      savedEnv.GOOGLE_SERVER_CLIENT_IDS = process.env.GOOGLE_SERVER_CLIENT_IDS;
      savedEnv.SMTP_USER = process.env.SMTP_USER;
      savedEnv.SMTP_PASS = process.env.SMTP_PASS;
      process.env.GOOGLE_CLIENT_ID = "web-client-1.apps.googleusercontent.com";
      process.env.GOOGLE_SERVER_CLIENT_IDS = "extra-client-2.apps.googleusercontent.com";
      delete process.env.SMTP_USER;
      delete process.env.SMTP_PASS;
    });

    afterEach(() => {
      mock.restoreAll();
      if (savedEnv.GOOGLE_CLIENT_ID === undefined) delete process.env.GOOGLE_CLIENT_ID;
      else process.env.GOOGLE_CLIENT_ID = savedEnv.GOOGLE_CLIENT_ID;
      if (savedEnv.GOOGLE_SERVER_CLIENT_IDS === undefined) delete process.env.GOOGLE_SERVER_CLIENT_IDS;
      else process.env.GOOGLE_SERVER_CLIENT_IDS = savedEnv.GOOGLE_SERVER_CLIENT_IDS;
      if (savedEnv.SMTP_USER === undefined) delete process.env.SMTP_USER;
      else process.env.SMTP_USER = savedEnv.SMTP_USER;
      if (savedEnv.SMTP_PASS === undefined) delete process.env.SMTP_PASS;
      else process.env.SMTP_PASS = savedEnv.SMTP_PASS;
    });

    it("register -> login (2-step OTP) -> /api/auth/me -> refresh rotation -> logout, plus domain enforcement", async () => {
      // Non-Unud emails are rejected
      const badSendOtp = await request("POST", "/api/auth/send-otp", {
        email: "outsider@gmail.com",
        purpose: "register",
      });
      assert.equal(badSendOtp.status, 400);

      const badRegDomain = await request("POST", "/api/auth/register", {
        email: "outsider@example.com",
        password: "Password123",
        full_name: "Outsider",
        prodi: "Informatika",
        angkatan: 2021,
        otp: "123456",
      });
      assert.equal(badRegDomain.status, 400);

      const badLoginDomain = await request("POST", "/api/auth/login", {
        email: "outsider@gmail.com",
        password: "Password123",
      });
      assert.equal(badLoginDomain.status, 400);

      // Step 1: request register OTP for student.unud.ac.id (and a second concurrent OTP for race-duplicate check)
      const otpRes = await request("POST", "/api/auth/send-otp", {
        email: "Budi@Student.Unud.ac.id",
        purpose: "register",
      });
      assert.equal(otpRes.status, 200);
      assert.ok(otpRes.body.otp_token);
      assert.ok(otpRes.body.dev_otp);

      const otpConcurrent = await request("POST", "/api/auth/send-otp", {
        email: "budi@student.unud.ac.id",
        purpose: "register",
      });
      assert.equal(otpConcurrent.status, 200);

      // Register without valid OTP fails with 400
      const noOtpReg = await request("POST", "/api/auth/register", {
        email: "Budi@Student.Unud.ac.id",
        password: "Password123",
        full_name: "Budi Santoso",
        prodi: "Informatika",
        angkatan: 2021,
      });
      assert.equal(noOtpReg.status, 400);

      // Step 2: complete registration with OTP
      const reg = await request("POST", "/api/auth/register", {
        email: "Budi@Student.Unud.ac.id",
        password: "Password123",
        full_name: "Budi Santoso",
        prodi: "Informatika",
        angkatan: 2021,
        otp: otpRes.body.dev_otp,
        otp_token: otpRes.body.otp_token,
      });
      assert.equal(reg.status, 201);
      assert.ok(reg.body.access_token);
      assert.ok(reg.body.refresh_token);
      assert.equal(reg.body.user.email, "budi@student.unud.ac.id");
      assert.equal(reg.body.user.full_name, "Budi Santoso");
      assert.equal(reg.body.user.avatar_url, null);

      // Duplicate email -> 409 on both /send-otp and /register (concurrent race)
      const dupOtp = await request("POST", "/api/auth/send-otp", {
        email: "budi@student.unud.ac.id",
        purpose: "register",
      });
      assert.equal(dupOtp.status, 409);

      const dup = await request("POST", "/api/auth/register", {
        email: "budi@student.unud.ac.id",
        password: "Password123",
        full_name: "Budi 2",
        prodi: "SI",
        angkatan: "2021",
        otp: otpConcurrent.body.dev_otp,
        otp_token: otpConcurrent.body.otp_token,
      });
      assert.equal(dup.status, 409);

      // Wrong password vs unknown email return identical 401
      const wrongPass = await request("POST", "/api/auth/login", {
        email: "budi@student.unud.ac.id",
        password: "WrongPassword",
      });
      const unknownEmail = await request("POST", "/api/auth/login", {
        email: "nobody@unud.ac.id",
        password: "WrongPassword",
      });
      assert.equal(wrongPass.status, 401);
      assert.equal(unknownEmail.status, 401);
      assert.equal(wrongPass.body.error, unknownEmail.body.error);

      // Valid login returns tokens & user directly (no OTP required on routine login)
      const login = await request("POST", "/api/auth/login", {
        email: "budi@student.unud.ac.id",
        password: "Password123",
      });
      assert.equal(login.status, 200);
      assert.equal(login.body.require_otp, undefined);
      assert.deepEqual(Object.keys(login.body).sort(), ["access_token", "refresh_token", "user"]);
      assert.deepEqual(
        Object.keys(login.body.user).sort(),
        ["avatar_url", "email", "full_name", "id", "role"]
      );

      // GET /api/auth/me
      const me = await request("GET", "/api/auth/me", null, {
        Authorization: `Bearer ${login.body.access_token}`,
      });
      assert.equal(me.status, 200);
      assert.equal(me.body.id, login.body.user.id);
      assert.equal(me.body.email, "budi@student.unud.ac.id");
      assert.equal(me.body.full_name, "Budi Santoso");

      // Refresh rotates token and invalidates the old refresh token
      const refreshed = await request("POST", "/api/auth/refresh", {
        refresh_token: login.body.refresh_token,
      });
      assert.equal(refreshed.status, 200);
      assert.ok(refreshed.body.access_token);
      assert.ok(refreshed.body.refresh_token);
      assert.notEqual(refreshed.body.refresh_token, login.body.refresh_token);

      const reuseOld = await request("POST", "/api/auth/refresh", {
        refresh_token: login.body.refresh_token,
      });
      assert.equal(reuseOld.status, 401);

      // Logout revokes refresh token
      const logout = await request("POST", "/api/auth/logout", {
        refresh_token: refreshed.body.refresh_token,
      });
      assert.equal(logout.status, 200);

      const afterLogout = await request("POST", "/api/auth/refresh", {
        refresh_token: refreshed.body.refresh_token,
      });
      assert.equal(afterLogout.status, 401);
    });

    it("POST /api/auth/google enforces Unud domains, verifies audience/email_verified, creates & links users", async () => {
      // 400 when id_token missing
      const emptyRes = await request("POST", "/api/auth/google", {});
      assert.equal(emptyRes.status, 400);

      // 503 when GOOGLE_CLIENT_ID missing
      process.env.GOOGLE_CLIENT_ID = "";
      delete process.env.GOOGLE_SERVER_CLIENT_IDS;
      const unconfiguredRes = await request("POST", "/api/auth/google", { id_token: "tok" });
      assert.equal(unconfiguredRes.status, 503);
      process.env.GOOGLE_CLIENT_ID = "web-client-1.apps.googleusercontent.com";
      process.env.GOOGLE_SERVER_CLIENT_IDS = "extra-client-2.apps.googleusercontent.com";

      // 401 when Google rejects token
      const badTokenRes = await request("POST", "/api/auth/google", { id_token: "invalid-tok" });
      assert.equal(badTokenRes.status, 401);

      // 403 when email_verified is not true
      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "g-1",
          email: "unverified@student.unud.ac.id",
          email_verified: false,
          name: "Unverified",
        }),
      }));
      const unverifiedRes = await request("POST", "/api/auth/google", { id_token: "unverified-tok" });
      assert.equal(unverifiedRes.status, 403);

      // 403 when email domain is not @unud.ac.id or @student.unud.ac.id
      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "g-outsider",
          email: "outsider@gmail.com",
          email_verified: true,
          name: "Outsider",
        }),
      }));
      const badDomainRes = await request("POST", "/api/auth/google", { id_token: "outsider-tok" });
      assert.equal(badDomainRes.status, 403);

      // 200 creates new user with exact /login shape and verifies audience list
      let capturedAudience;
      googleMock.mock.mockImplementationOnce(async ({ audience }) => {
        capturedAudience = audience;
        return {
          getPayload: () => ({
            sub: "google-sub-123",
            email: "Siti.Alumni@student.unud.ac.id",
            email_verified: true,
            name: "Siti Alumni",
            picture: "https://lh3.googleusercontent.com/a/avatar",
          }),
        };
      });
      const createdRes = await request("POST", "/api/auth/google", { id_token: "valid-google-tok" });
      assert.equal(createdRes.status, 200);
      assert.deepEqual(capturedAudience, [
        "web-client-1.apps.googleusercontent.com",
        "extra-client-2.apps.googleusercontent.com",
      ]);
      assert.deepEqual(Object.keys(createdRes.body).sort(), ["access_token", "refresh_token", "user"]);
      assert.deepEqual(
        Object.keys(createdRes.body.user).sort(),
        ["avatar_url", "email", "full_name", "id", "role"]
      );
      assert.equal(createdRes.body.user.full_name, "Siti Alumni");
      assert.equal(createdRes.body.user.avatar_url, "https://lh3.googleusercontent.com/a/avatar");

      // Google-only user cannot log in with password
      const passLogin = await request("POST", "/api/auth/login", {
        email: createdRes.body.user.email,
        password: "!no-password",
      });
      assert.equal(passLogin.status, 401);

      // Conflicting google_sub for same email returns 409
      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "different-google-sub",
          email: "Siti.Alumni@student.unud.ac.id",
          email_verified: true,
          name: "Impostor",
        }),
      }));
      const conflictRes = await request("POST", "/api/auth/google", { id_token: "other-tok" });
      assert.equal(conflictRes.status, 409);

      // Existing email+password user (@unud.ac.id) links Google sub cleanly on first Google sign-in
      const manualOtp = await request("POST", "/api/auth/send-otp", {
        email: "manual@unud.ac.id",
        purpose: "register",
      });
      await request("POST", "/api/auth/register", {
        email: "manual@unud.ac.id",
        password: "Password123",
        full_name: "Manual User",
        prodi: "Elektro",
        angkatan: "2020",
        otp: manualOtp.body.dev_otp,
        otp_token: manualOtp.body.otp_token,
      });
      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "google-sub-manual",
          email: "manual@unud.ac.id",
          email_verified: true,
          name: "Manual User",
          picture: "https://lh3.googleusercontent.com/a/manual",
        }),
      }));
      const linkedRes = await request("POST", "/api/auth/google", { id_token: "link-tok" });
      assert.equal(linkedRes.status, 200);
      assert.equal(linkedRes.body.user.full_name, "Manual User");
      assert.equal(linkedRes.body.user.avatar_url, "https://lh3.googleusercontent.com/a/manual");
      const dbUser = db.tables.users.find((u) => u.email === "manual@unud.ac.id");
      assert.equal(dbUser.google_sub, "google-sub-manual");
    });

    it("forgot-password & reset-password hash OTP, enforce domain & attempt limit, and revoke refresh tokens", async () => {
      const regOtp = await request("POST", "/api/auth/send-otp", {
        email: "reset@unud.ac.id",
        purpose: "register",
      });
      await request("POST", "/api/auth/register", {
        email: "reset@unud.ac.id",
        password: "OldPassword1",
        full_name: "Reset User",
        prodi: "Informatika",
        angkatan: "2022",
        otp: regOtp.body.dev_otp,
        otp_token: regOtp.body.otp_token,
      });

      // Non-Unud email rejected
      const badDomainForgot = await request("POST", "/api/auth/forgot-password", {
        email: "unknown@example.com",
      });
      assert.equal(badDomainForgot.status, 400);

      // Anti-enumeration on unknown Unud email
      const unknownForgot = await request("POST", "/api/auth/forgot-password", {
        email: "unknown@unud.ac.id",
      });
      assert.equal(unknownForgot.status, 200);
      assert.equal(unknownForgot.body.dev_otp, undefined);

      const forgot = await request("POST", "/api/auth/forgot-password", {
        email: "reset@unud.ac.id",
      });
      assert.equal(forgot.status, 200);
      assert.ok(forgot.body.dev_otp);
      // Stored OTP must be HMAC digest, never plaintext
      assert.notEqual(db.tables.password_reset_otps[0].otp_code, forgot.body.dev_otp);

      // 5 wrong attempts invalidate the OTP
      for (let i = 0; i < 6; i++) {
        const bad = await request("POST", "/api/auth/reset-password", {
          email: "reset@unud.ac.id",
          otp: "000000",
          new_password: "NewPassword1",
        });
        assert.equal(bad.status, 400);
      }
      assert.equal(db.tables.password_reset_otps[0].used, true);

      // Fresh OTP works and revokes existing sessions
      const forgot2 = await request("POST", "/api/auth/forgot-password", {
        email: "reset@unud.ac.id",
      });
      const resetOk = await request("POST", "/api/auth/reset-password", {
        email: "reset@unud.ac.id",
        otp: forgot2.body.dev_otp,
        new_password: "NewPassword1",
      });
      assert.equal(resetOk.status, 200);

      const loginNew = await request("POST", "/api/auth/login", {
        email: "reset@unud.ac.id",
        password: "NewPassword1",
      });
      assert.equal(loginNew.status, 200);
      assert.ok(loginNew.body.access_token);
    });

    it("change-password works for password users, revokes refresh token, and blocks Google-only users", async () => {
      const cpOtp = await request("POST", "/api/auth/send-otp", {
        email: "cp@unud.ac.id",
        purpose: "register",
      });
      const reg = await request("POST", "/api/auth/register", {
        email: "cp@unud.ac.id",
        password: "Password123",
        full_name: "CP User",
        prodi: "SI",
        angkatan: "2021",
        otp: cpOtp.body.dev_otp,
        otp_token: cpOtp.body.otp_token,
      });
      assert.equal(reg.status, 201);

      const wrongCur = await request(
        "POST",
        "/api/auth/change-password",
        { current_password: "WrongPassword", new_password: "Password456" },
        { Authorization: `Bearer ${reg.body.access_token}` }
      );
      assert.equal(wrongCur.status, 401);

      const ok = await request(
        "POST",
        "/api/auth/change-password",
        { current_password: "Password123", new_password: "Password456" },
        { Authorization: `Bearer ${reg.body.access_token}` }
      );
      assert.equal(ok.status, 200);
      assert.ok(ok.headers["ratelimit"]);

      // Old refresh token was revoked on password change
      const oldRefresh = await request("POST", "/api/auth/refresh", {
        refresh_token: reg.body.refresh_token,
      });
      assert.equal(oldRefresh.status, 401);

      // Google-only user gets 400 when trying change-password
      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "g-cp-1",
          email: "gonly@student.unud.ac.id",
          email_verified: true,
          name: "G Only",
        }),
      }));
      const gRes = await request("POST", "/api/auth/google", { id_token: "g-tok" });
      assert.equal(gRes.status, 200);

      const gChange = await request(
        "POST",
        "/api/auth/change-password",
        { current_password: "anything", new_password: "NewPassword123" },
        { Authorization: `Bearer ${gRes.body.access_token}` }
      );
      assert.equal(gChange.status, 400);
    });

    it("sends OTP via SMTP no-reply when SMTP env is configured", async () => {
      const nodemailer = require("nodemailer");
      const sentMails = [];
      mock.method(nodemailer, "createTransport", () => ({
        sendMail: async (msg) => {
          sentMails.push(msg);
          return { messageId: "smtp-msg-1" };
        },
      }));

      const prev = {
        SMTP_HOST: process.env.SMTP_HOST,
        SMTP_USER: process.env.SMTP_USER,
        SMTP_PASS: process.env.SMTP_PASS,
        EMAIL_FROM: process.env.EMAIL_FROM,
      };
      process.env.SMTP_HOST = "smtp.gmail.com";
      process.env.SMTP_USER = "unitas.noreply@gmail.com";
      process.env.SMTP_PASS = "app-password-test";
      process.env.EMAIL_FROM = "Unitas No-Reply <noreply@unud.ac.id>";

      try {
        const res = await request("POST", "/api/auth/send-otp", {
          email: "smtp.test@student.unud.ac.id",
          purpose: "register",
        });
        assert.equal(res.status, 200);
        assert.equal(res.body.dev_otp, undefined);
        assert.ok(res.body.otp_token);
        assert.equal(sentMails.length, 1);
        assert.equal(sentMails[0].to, "smtp.test@student.unud.ac.id");
        assert.equal(sentMails[0].replyTo, "noreply@unud.ac.id");
        assert.match(sentMails[0].text, /\d{6}/);
      } finally {
        for (const [k, v] of Object.entries(prev)) {
          if (v === undefined) delete process.env[k];
          else process.env[k] = v;
        }
      }
    });
  });
});
