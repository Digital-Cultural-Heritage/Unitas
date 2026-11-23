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
const jwt = require("jsonwebtoken");

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
    const [meRes, delMeRes, setPwRes, onboardRes, postsRes, notifRes, msgRes, jobsRes, appliedRes, applyRes, applicantsRes, statusRes, cvRes] = await Promise.all([
      request("GET", "/api/auth/me"),
      request("DELETE", "/api/users/me"),
      request("POST", "/api/auth/set-password", { new_password: "Password123" }),
      request("POST", "/api/auth/complete-onboarding", { full_name: "Test", prodi: "TI", angkatan: "2022" }),
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
    assert.equal(delMeRes.status, 401);
    assert.equal(setPwRes.status, 401);
    assert.equal(onboardRes.status, 401);
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
      assert.equal(reg.body.user.has_password, true);

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
        [
          "angkatan",
          "avatar_url",
          "email",
          "full_name",
          "has_password",
          "id",
          "kota",
          "pekerjaan",
          "perusahaan",
          "prodi",
          "profile_completed",
          "role",
        ]
      );
      assert.equal(login.body.user.has_password, true);
      assert.equal(login.body.user.profile_completed, true);
      assert.equal(login.body.user.password_hash, undefined);

      // GET /api/auth/me
      const me = await request("GET", "/api/auth/me", null, {
        Authorization: `Bearer ${login.body.access_token}`,
      });
      assert.equal(me.status, 200);
      assert.equal(me.body.id, login.body.user.id);
      assert.equal(me.body.email, "budi@student.unud.ac.id");
      assert.equal(me.body.full_name, "Budi Santoso");
      assert.equal(me.body.has_password, true);
      assert.equal(me.body.password_hash, undefined);

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
        [
          "angkatan",
          "avatar_url",
          "email",
          "full_name",
          "has_password",
          "id",
          "kota",
          "pekerjaan",
          "perusahaan",
          "prodi",
          "profile_completed",
          "role",
        ]
      );
      assert.equal(createdRes.body.user.full_name, "Siti Alumni");
      assert.equal(createdRes.body.user.avatar_url, "https://lh3.googleusercontent.com/a/avatar");
      assert.equal(createdRes.body.user.has_password, false);
      assert.equal(createdRes.body.user.profile_completed, false);
      assert.equal(createdRes.body.user.password_hash, undefined);

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
      assert.equal(linkedRes.body.user.has_password, true);
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

    it("set-password lets a Google-only user create a password, preserves session, and enables email+password login", async () => {
      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "g-setpw-1",
          email: "setpw@student.unud.ac.id",
          email_verified: true,
          name: "Set Password User",
        }),
      }));
      const gRes = await request("POST", "/api/auth/google", { id_token: "g-setpw-tok" });
      assert.equal(gRes.status, 200);
      assert.equal(gRes.body.user.has_password, false);

      // Both /api/auth/me and /api/users/me reflect has_password === false without leaking password_hash
      const authMeBefore = await request("GET", "/api/auth/me", null, {
        Authorization: `Bearer ${gRes.body.access_token}`,
      });
      assert.equal(authMeBefore.status, 200);
      assert.equal(authMeBefore.body.has_password, false);
      assert.equal(authMeBefore.body.password_hash, undefined);

      const usersMeBefore = await request("GET", "/api/users/me", null, {
        Authorization: `Bearer ${gRes.body.access_token}`,
      });
      assert.equal(usersMeBefore.status, 200);
      assert.equal(usersMeBefore.body.has_password, false);
      assert.equal(usersMeBefore.body.password_hash, undefined);

      // Validation rejects short and >72-byte passwords
      const shortPw = await request(
        "POST",
        "/api/auth/set-password",
        { new_password: "123" },
        { Authorization: `Bearer ${gRes.body.access_token}` }
      );
      assert.equal(shortPw.status, 400);

      const longPw = await request(
        "POST",
        "/api/auth/set-password",
        { new_password: "a".repeat(73) },
        { Authorization: `Bearer ${gRes.body.access_token}` }
      );
      assert.equal(longPw.status, 400);

      // Logged-out Google-only user's old access token cannot call /set-password
      await request("POST", "/api/auth/logout", { refresh_token: gRes.body.refresh_token });
      const loggedOutSetPw = await request(
        "POST",
        "/api/auth/set-password",
        { new_password: "NewPassword123" },
        { Authorization: `Bearer ${gRes.body.access_token}` }
      );
      assert.equal(loggedOutSetPw.status, 401);

      // Re-login with Google restores session and refresh_token
      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "g-setpw-1",
          email: "setpw@student.unud.ac.id",
          email_verified: true,
          name: "Set Password User",
        }),
      }));
      const gRelogin = await request("POST", "/api/auth/google", { id_token: "g-setpw-tok-relogin" });
      assert.equal(gRelogin.status, 200);
      assert.equal(gRelogin.body.user.has_password, false);

      // Setting valid password succeeds and keeps current session's refresh token alive
      const setOk = await request(
        "POST",
        "/api/auth/set-password",
        { new_password: "NewPassword123" },
        { Authorization: `Bearer ${gRelogin.body.access_token}` }
      );
      assert.equal(setOk.status, 200);
      assert.equal(setOk.body.has_password, true);

      const refreshStillWorks = await request("POST", "/api/auth/refresh", {
        refresh_token: gRelogin.body.refresh_token,
      });
      assert.equal(refreshStillWorks.status, 200);
      assert.ok(refreshStillWorks.body.access_token);

      // Re-calling /set-password once password exists is blocked with 400
      const setAgain = await request(
        "POST",
        "/api/auth/set-password",
        { new_password: "AnotherPassword123" },
        { Authorization: `Bearer ${gRes.body.access_token}` }
      );
      assert.equal(setAgain.status, 400);

      // /api/auth/me and /api/users/me now reflect has_password === true without leaking password_hash
      const authMeAfter = await request("GET", "/api/auth/me", null, {
        Authorization: `Bearer ${gRes.body.access_token}`,
      });
      assert.equal(authMeAfter.status, 200);
      assert.equal(authMeAfter.body.has_password, true);
      assert.equal(authMeAfter.body.password_hash, undefined);

      const usersMeAfter = await request("GET", "/api/users/me", null, {
        Authorization: `Bearer ${gRes.body.access_token}`,
      });
      assert.equal(usersMeAfter.status, 200);
      assert.equal(usersMeAfter.body.has_password, true);
      assert.equal(usersMeAfter.body.password_hash, undefined);

      // Email + password login works now
      const emailLogin = await request("POST", "/api/auth/login", {
        email: "setpw@student.unud.ac.id",
        password: "NewPassword123",
      });
      assert.equal(emailLogin.status, 200);
      assert.equal(emailLogin.body.user.has_password, true);

      // Google login still works and reports has_password === true
      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "g-setpw-1",
          email: "setpw@student.unud.ac.id",
          email_verified: true,
          name: "Set Password User",
        }),
      }));
      const googleLoginAgain = await request("POST", "/api/auth/google", { id_token: "g-setpw-tok-2" });
      assert.equal(googleLoginAgain.status, 200);
      assert.equal(googleLoginAgain.body.user.has_password, true);

      // change-password works using the newly created password
      const changeOk = await request(
        "POST",
        "/api/auth/change-password",
        { current_password: "NewPassword123", new_password: "ChangedPassword456" },
        { Authorization: `Bearer ${emailLogin.body.access_token}` }
      );
      assert.equal(changeOk.status, 200);
    });

    it("sends OTP via SMTP no-reply when SMTP env is configured and returns 502 if SMTP fails", async () => {
      const nodemailer = require("nodemailer");
      const sentMails = [];
      let shouldFailSmtp = false;
      mock.method(nodemailer, "createTransport", () => ({
        sendMail: async (msg) => {
          if (shouldFailSmtp) throw new Error("SMTP connection refused");
          sentMails.push(msg);
          return { messageId: "smtp-msg-1" };
        },
      }));

      const prev = {
        SMTP_HOST: process.env.SMTP_HOST,
        SMTP_USER: process.env.SMTP_USER,
        SMTP_PASS: process.env.SMTP_PASS,
        EMAIL_FROM: process.env.EMAIL_FROM,
        EMAIL_REPLY_TO: process.env.EMAIL_REPLY_TO,
      };
      process.env.SMTP_HOST = "smtp.gmail.com";
      process.env.SMTP_USER = "unitas.noreply@gmail.com";
      process.env.SMTP_PASS = "app-password-test";
      process.env.EMAIL_FROM = "Unitas No-Reply <noreply@unud.ac.id>";
      delete process.env.EMAIL_REPLY_TO;

      try {
        const res = await request("POST", "/api/auth/send-otp", {
          email: "smtp.test@student.unud.ac.id",
          purpose: "register",
        });
        assert.equal(res.status, 200);
        assert.equal(res.body.dev_otp, undefined);
        assert.ok(res.body.otp_token);
        assert.equal(sentMails.length, 1);
        assert.equal(sentMails[0].from, "Unitas <unitas.noreply@gmail.com>");
        assert.equal(sentMails[0].to, "smtp.test@student.unud.ac.id");
        assert.equal(sentMails[0].replyTo, "unitas.noreply@gmail.com");
        assert.match(sentMails[0].subject, /\d{6}/);
        assert.match(sentMails[0].text, /\d{6}/);
        assert.match(sentMails[0].html, /\d{6}/);
        assert.doesNotMatch(sentMails[0].text, /no-reply/i);
        assert.doesNotMatch(sentMails[0].html, /no-reply/i);

        // Registered user hitting forgot-password when SMTP fails must receive 502 (not silent 200)
        db.tables.users.push({
          id: crypto.randomUUID(),
          email: "smtp.user@unud.ac.id",
          password_hash: "$2b$04$dummyhashvalueforunittesting1234567890123456",
          role: "alumni",
        });
        shouldFailSmtp = true;
        const forgotFail = await request("POST", "/api/auth/forgot-password", {
          email: "smtp.user@unud.ac.id",
        });
        assert.equal(forgotFail.status, 502);
      } finally {
        for (const [k, v] of Object.entries(prev)) {
          if (v === undefined) delete process.env[k];
          else process.env[k] = v;
        }
      }
    });
  });

  describe("Auth security & all login scenarios", () => {
    let db;
    let googleMock;
    let secServer;
    let prevBaseUrl;
    let savedIndexCache;
    let savedAuthCache;
    const savedEnv = {};

    before(async () => {
      prevBaseUrl = baseUrl;
      const indexPath = require.resolve("../api/index");
      const authPath = require.resolve("../src/routes/auth");
      savedIndexCache = require.cache[indexPath];
      savedAuthCache = require.cache[authPath];
      delete require.cache[indexPath];
      delete require.cache[authPath];

      const secApp = require("../api/index");
      secServer = secApp.listen(0);
      await new Promise((resolve) => secServer.once("listening", resolve));
      const { port } = secServer.address();
      baseUrl = `http://127.0.0.1:${port}`;
    });

    after(async () => {
      if (secServer) await new Promise((resolve) => secServer.close(resolve));
      baseUrl = prevBaseUrl;
      const indexPath = require.resolve("../api/index");
      const authPath = require.resolve("../src/routes/auth");
      if (savedIndexCache) require.cache[indexPath] = savedIndexCache;
      else delete require.cache[indexPath];
      if (savedAuthCache) require.cache[authPath] = savedAuthCache;
      else delete require.cache[authPath];
    });

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

    it("JWT forgery, expiry, and token-type confusion are rejected with 401", async () => {
      // alg:none unsigned token
      const noneHeader = Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url");
      const nonePayload = Buffer.from(
        JSON.stringify({ userId: "u-1", email: "a@unud.ac.id", role: "alumni", typ: "access" })
      ).toString("base64url");
      const algNoneToken = `${noneHeader}.${nonePayload}.`;
      const noneRes = await request("GET", "/api/auth/me", null, {
        Authorization: `Bearer ${algNoneToken}`,
      });
      assert.equal(noneRes.status, 401);

      // Token signed with wrong secret
      const wrongSecretToken = jwt.sign(
        { userId: "u-1", email: "a@unud.ac.id", role: "alumni", typ: "access" },
        "wrong-secret-key",
        { algorithm: "HS256", expiresIn: "1h" }
      );
      const wrongRes = await request("GET", "/api/auth/me", null, {
        Authorization: `Bearer ${wrongSecretToken}`,
      });
      assert.equal(wrongRes.status, 401);

      // Expired access token
      const expiredToken = jwt.sign(
        { userId: "u-1", email: "a@unud.ac.id", role: "alumni", typ: "access" },
        process.env.JWT_SECRET,
        { algorithm: "HS256", expiresIn: -10 }
      );
      const expRes = await request("GET", "/api/auth/me", null, {
        Authorization: `Bearer ${expiredToken}`,
      });
      assert.equal(expRes.status, 401);

      // otp_token (signed by JWT_SECRET, typ: "email_otp") rejected as Bearer auth token
      const otpRes = await request("POST", "/api/auth/send-otp", {
        email: "jwt.check@student.unud.ac.id",
        purpose: "register",
      });
      assert.equal(otpRes.status, 200);
      const otpAsBearer = await request("GET", "/api/auth/me", null, {
        Authorization: `Bearer ${otpRes.body.otp_token}`,
      });
      assert.equal(otpAsBearer.status, 401);
    });

    it("Campus domain bypass tricks are blocked across auth endpoints", async () => {
      const sendOtpBypasses = ["evil@student.unud.ac.id.attacker.com", "evil@fakeunud.ac.id"];
      for (const email of sendOtpBypasses) {
        const otpRes = await request("POST", "/api/auth/send-otp", { email, purpose: "register" });
        assert.equal(otpRes.status, 400);
      }

      const registerBypasses = ["evil@sub.student.unud.ac.id", '"a@unud.ac.id"@gmail.com'];
      for (const email of registerBypasses) {
        const regRes = await request("POST", "/api/auth/register", {
          email,
          password: "Password123",
          full_name: "Evil Bypass",
          prodi: "TI",
          angkatan: "2022",
          otp: "123456",
        });
        assert.equal(regRes.status, 400);
      }

      const allBypasses = [...sendOtpBypasses, ...registerBypasses];
      for (const email of allBypasses) {
        const loginRes = await request("POST", "/api/auth/login", { email, password: "Password123" });
        assert.equal(loginRes.status, 400);

        const forgotRes = await request("POST", "/api/auth/forgot-password", { email });
        assert.equal(forgotRes.status, 400);

        googleMock.mock.mockImplementationOnce(async () => ({
          getPayload: () => ({
            sub: `sub-${email}`,
            email,
            email_verified: true,
            name: "Bypass User",
          }),
        }));
        const gRes = await request("POST", "/api/auth/google", { id_token: `tok-${email}` });
        assert.equal(gRes.status, 403);
      }
    });

    it("OTP abuse, cross-email swap, malformed OTP, lockout, replay, and role escalation are blocked", async () => {
      // Dead purpose: "login" on /send-otp must be rejected
      const loginPurposeRes = await request("POST", "/api/auth/send-otp", {
        email: "alice@student.unud.ac.id",
        purpose: "login",
      });
      assert.equal(loginPurposeRes.status, 400);

      // Issue OTP for Alice
      const aliceOtp = await request("POST", "/api/auth/send-otp", {
        email: "alice@student.unud.ac.id",
        purpose: "register",
      });
      assert.equal(aliceOtp.status, 200);

      // Using Alice's otp_token to register Bob fails
      const swapRes = await request("POST", "/api/auth/register", {
        email: "bob@student.unud.ac.id",
        password: "Password123",
        full_name: "Bob",
        prodi: "SI",
        angkatan: "2021",
        otp: aliceOtp.body.dev_otp,
        otp_token: aliceOtp.body.otp_token,
      });
      assert.equal(swapRes.status, 400);

      // Malformed OTP types (array & object) fail cleanly with 400
      for (const badOtp of [["123", "456"], {}]) {
        const badOtpRes = await request("POST", "/api/auth/register", {
          email: "alice@student.unud.ac.id",
          password: "Password123",
          full_name: "Alice",
          prodi: "TI",
          angkatan: "2022",
          otp: badOtp,
          otp_token: aliceOtp.body.otp_token,
        });
        assert.equal(badOtpRes.status, 400);
      }

      // Role escalation attempt (role: "admin") is ignored -> forced to "alumni"
      const aliceReg = await request("POST", "/api/auth/register", {
        email: "alice@student.unud.ac.id",
        password: "Password123",
        full_name: "Alice",
        prodi: "TI",
        angkatan: "2022",
        role: "admin",
        otp: aliceOtp.body.dev_otp,
        otp_token: aliceOtp.body.otp_token,
      });
      assert.equal(aliceReg.status, 201);
      assert.equal(aliceReg.body.user.role, "alumni");
      assert.equal(db.tables.users.find((u) => u.email === "alice@student.unud.ac.id").role, "alumni");

      // 5 wrong register OTP attempts lock out even the real dev_otp
      const lockOtp = await request("POST", "/api/auth/send-otp", {
        email: "lockout@student.unud.ac.id",
        purpose: "register",
      });
      assert.equal(lockOtp.status, 200);
      for (let i = 0; i < 5; i++) {
        const wrong = await request("POST", "/api/auth/register", {
          email: "lockout@student.unud.ac.id",
          password: "Password123",
          full_name: "Lockout",
          prodi: "TI",
          angkatan: "2022",
          otp: "000000",
          otp_token: lockOtp.body.otp_token,
        });
        assert.equal(wrong.status, 400);
      }
      const lockedReal = await request("POST", "/api/auth/register", {
        email: "lockout@student.unud.ac.id",
        password: "Password123",
        full_name: "Lockout",
        prodi: "TI",
        angkatan: "2022",
        otp: lockOtp.body.dev_otp,
        otp_token: lockOtp.body.otp_token,
      });
      assert.equal(lockedReal.status, 400);

      // Replaying an already-used password reset OTP fails with 400
      const forgot = await request("POST", "/api/auth/forgot-password", {
        email: "alice@student.unud.ac.id",
      });
      assert.equal(forgot.status, 200);
      const resetOk = await request("POST", "/api/auth/reset-password", {
        email: "alice@student.unud.ac.id",
        otp: forgot.body.dev_otp,
        new_password: "AliceNewPassword1",
      });
      assert.equal(resetOk.status, 200);
      const resetReplay = await request("POST", "/api/auth/reset-password", {
        email: "alice@student.unud.ac.id",
        otp: forgot.body.dev_otp,
        new_password: "AliceReplayPass1",
      });
      assert.equal(resetReplay.status, 400);
    });

    it("Google Sign-In duplicate google_sub (23505) does not fall back to inserting a duplicate row", async () => {
      let usersInserts = 0;
      const origFrom = db.from;
      mock.restoreAll();
      mock.method(supabase, "from", (table) => {
        const b = origFrom(table);
        if (table !== "users") return b;
        const origInsert = b.insert.bind(b);
        b.insert = (row) => {
          usersInserts++;
          origInsert(row);
          if (usersInserts === 1) {
            // Simulate concurrent Google signup winning the race before our insert
            const winnerId = crypto.randomUUID();
            db.tables.users.push({
              id: winnerId,
              email: "race.google@student.unud.ac.id",
              password_hash: "!no-password",
              role: "alumni",
              google_sub: "dup-sub-1",
            });
            db.tables.user_profiles.push({
              id: crypto.randomUUID(),
              user_id: winnerId,
              full_name: "Race Winner",
              avatar_url: null,
            });
            b.then = (resolve) =>
              resolve({
                data: null,
                error: {
                  code: "23505",
                  message: 'duplicate key value violates unique constraint "idx_users_google_sub"',
                },
              });
          }
          return b;
        };
        return b;
      });

      const { OAuth2Client } = require("google-auth-library");
      googleMock = mock.method(OAuth2Client.prototype, "verifyIdToken", async () => ({
        getPayload: () => ({
          sub: "dup-sub-1",
          email: "race.google@student.unud.ac.id",
          email_verified: true,
          name: "Race Winner",
        }),
      }));

      const res = await request("POST", "/api/auth/google", { id_token: "dup-sub-tok" });
      assert.equal(res.status, 200);
      assert.equal(usersInserts, 1);
      assert.equal(db.tables.users.length, 1);
      assert.equal(db.tables.users.filter((u) => !u.google_sub).length, 0);
    });

    it("Concurrent set-password race, post-logout revocation, and delete -> re-register lifecycle", async () => {
      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "g-race-1",
          email: "race@student.unud.ac.id",
          email_verified: true,
          name: "Race User",
        }),
      }));
      const gRes = await request("POST", "/api/auth/google", { id_token: "g-race-tok" });
      assert.equal(gRes.status, 200);
      assert.equal(gRes.body.user.has_password, false);

      // Concurrent set-password calls -> only one succeeds (200), the other loses atomicity check (409)
      const [sp1, sp2] = await Promise.all([
        request(
          "POST",
          "/api/auth/set-password",
          { new_password: "RacePassword1" },
          { Authorization: `Bearer ${gRes.body.access_token}` }
        ),
        request(
          "POST",
          "/api/auth/set-password",
          { new_password: "RacePassword1" },
          { Authorization: `Bearer ${gRes.body.access_token}` }
        ),
      ]);
      assert.deepEqual([sp1.status, sp2.status].sort((a, b) => a - b), [200, 409]);

      // Subsequent set-password fails because password now exists
      const spAfter = await request(
        "POST",
        "/api/auth/set-password",
        { new_password: "RacePassword1" },
        { Authorization: `Bearer ${gRes.body.access_token}` }
      );
      assert.equal(spAfter.status, 400);

      // After logout, unexpired access_token is rejected (401) across sensitive mutation endpoints
      const logoutRes = await request("POST", "/api/auth/logout", {
        refresh_token: gRes.body.refresh_token,
      });
      assert.equal(logoutRes.status, 200);

      const authHeaders = { Authorization: `Bearer ${gRes.body.access_token}` };
      const [outSet, outChange, outDel] = await Promise.all([
        request("POST", "/api/auth/set-password", { new_password: "RacePassword2" }, authHeaders),
        request(
          "POST",
          "/api/auth/change-password",
          { current_password: "RacePassword1", new_password: "RacePassword2" },
          authHeaders
        ),
        request("DELETE", "/api/users/me", null, authHeaders),
      ]);
      assert.equal(outSet.status, 401);
      assert.equal(outChange.status, 401);
      assert.equal(outDel.status, 401);
      assert.equal(db.tables.users.length, 1);

      // Log back in via email+password, then delete account
      const loginAgain = await request("POST", "/api/auth/login", {
        email: "race@student.unud.ac.id",
        password: "RacePassword1",
      });
      assert.equal(loginAgain.status, 200);

      const freshHeaders = { Authorization: `Bearer ${loginAgain.body.access_token}` };
      const delRes = await request("DELETE", "/api/users/me", null, freshHeaders);
      assert.equal(delRes.status, 200);
      assert.equal(db.tables.users.length, 0);

      // Old tokens no longer grant access after deletion
      const deadRefresh = await request("POST", "/api/auth/refresh", {
        refresh_token: loginAgain.body.refresh_token,
      });
      assert.equal(deadRefresh.status, 401);

      const [deadMe, deadSet, deadChange, deadDel] = await Promise.all([
        request("GET", "/api/auth/me", null, freshHeaders),
        request("POST", "/api/auth/set-password", { new_password: "RacePassword2" }, freshHeaders),
        request(
          "POST",
          "/api/auth/change-password",
          { current_password: "RacePassword1", new_password: "RacePassword2" },
          freshHeaders
        ),
        request("DELETE", "/api/users/me", null, freshHeaders),
      ]);
      assert.equal(deadMe.status, 404);
      assert.equal(deadSet.status, 404);
      assert.equal(deadChange.status, 404);
      assert.equal(deadDel.status, 404);

      // Deleted user's Unud email can re-register via OTP and log in again
      const reregOtp = await request("POST", "/api/auth/send-otp", {
        email: "race@student.unud.ac.id",
        purpose: "register",
      });
      assert.equal(reregOtp.status, 200);
      const rereg = await request("POST", "/api/auth/register", {
        email: "race@student.unud.ac.id",
        password: "ReRegistered1",
        full_name: "Race User Reborn",
        prodi: "TI",
        angkatan: "2023",
        otp: reregOtp.body.dev_otp,
        otp_token: reregOtp.body.otp_token,
      });
      assert.equal(rereg.status, 201);

      const relogin = await request("POST", "/api/auth/login", {
        email: "race@student.unud.ac.id",
        password: "ReRegistered1",
      });
      assert.equal(relogin.status, 200);
      assert.equal(relogin.body.user.has_password, true);
    });
  });

  describe("OTP delivery hardening & Google duplicate account handling", () => {
    let db;
    let googleMock;
    let otpServer;
    let prevBaseUrl;
    let savedIndexCache;
    let savedAuthCache;
    const savedEnv = {};

    before(async () => {
      prevBaseUrl = baseUrl;
      const indexPath = require.resolve("../api/index");
      const authPath = require.resolve("../src/routes/auth");
      savedIndexCache = require.cache[indexPath];
      savedAuthCache = require.cache[authPath];
      delete require.cache[indexPath];
      delete require.cache[authPath];

      const otpApp = require("../api/index");
      otpServer = otpApp.listen(0);
      await new Promise((resolve) => otpServer.once("listening", resolve));
      const { port } = otpServer.address();
      baseUrl = `http://127.0.0.1:${port}`;
    });

    after(async () => {
      if (otpServer) await new Promise((resolve) => otpServer.close(resolve));
      baseUrl = prevBaseUrl;
      const indexPath = require.resolve("../api/index");
      const authPath = require.resolve("../src/routes/auth");
      if (savedIndexCache) require.cache[indexPath] = savedIndexCache;
      else delete require.cache[indexPath];
      if (savedAuthCache) require.cache[authPath] = savedAuthCache;
      else delete require.cache[authPath];
    });

    beforeEach(() => {
      db = createMockDb();
      mock.method(supabase, "from", (table) => db.from(table));

      const { OAuth2Client } = require("google-auth-library");
      googleMock = mock.method(OAuth2Client.prototype, "verifyIdToken", async () => {
        throw new Error("unexpected verifyIdToken call");
      });

      for (const k of [
        "NODE_ENV",
        "VERCEL",
        "GOOGLE_CLIENT_ID",
        "GOOGLE_SERVER_CLIENT_IDS",
        "SMTP_HOST",
        "SMTP_PORT",
        "SMTP_SECURE",
        "SMTP_USER",
        "SMTP_PASS",
        "RESEND_API_KEY",
        "EMAIL_FROM",
        "EMAIL_REPLY_TO",
      ]) {
        savedEnv[k] = process.env[k];
      }
      process.env.NODE_ENV = "test";
      delete process.env.VERCEL;
      process.env.GOOGLE_CLIENT_ID = "web-client-1.apps.googleusercontent.com";
      delete process.env.GOOGLE_SERVER_CLIENT_IDS;
      delete process.env.SMTP_USER;
      delete process.env.SMTP_PASS;
      delete process.env.RESEND_API_KEY;
    });

    afterEach(() => {
      mock.restoreAll();
      for (const [k, v] of Object.entries(savedEnv)) {
        if (v === undefined) delete process.env[k];
        else process.env[k] = v;
      }
    });

    it("fails with 503 in production when SMTP/Resend env vars are missing", async () => {
      process.env.NODE_ENV = "production";
      delete process.env.SMTP_HOST;
      delete process.env.SMTP_USER;
      delete process.env.SMTP_PASS;
      delete process.env.RESEND_API_KEY;

      const sendOtpRes = await request("POST", "/api/auth/send-otp", {
        email: "prod.check@student.unud.ac.id",
        purpose: "register",
      });
      assert.equal(sendOtpRes.status, 503);
      assert.equal(sendOtpRes.body.dev_otp, undefined);

      const forgotRes = await request("POST", "/api/auth/forgot-password", {
        email: "prod.check@student.unud.ac.id",
      });
      assert.equal(forgotRes.status, 503);
      assert.equal(forgotRes.body.dev_otp, undefined);
    });

    it("returns 502 when SMTP rejects the recipient", async () => {
      const nodemailer = require("nodemailer");
      let createTransportCalls = 0;
      mock.method(nodemailer, "createTransport", () => {
        createTransportCalls++;
        return {
          sendMail: async () => ({
            messageId: "smtp-rej-1",
            rejected: ["user@student.unud.ac.id"],
          }),
        };
      });

      process.env.SMTP_HOST = "smtp.gmail.com";
      process.env.SMTP_USER = "unitas.rejected.test@gmail.com";
      process.env.SMTP_PASS = "app-password-rejected-test";

      const res = await request("POST", "/api/auth/send-otp", {
        email: "user@student.unud.ac.id",
        purpose: "register",
      });
      assert.equal(res.status, 502);
      assert.equal(createTransportCalls, 1);
    });

    it("returns 409 with Google sign-in guidance when email belongs to a Google-only account", async () => {
      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "g-only-dup-1",
          email: "google.user@student.unud.ac.id",
          email_verified: true,
          name: "Google User",
        }),
      }));
      const gRes = await request("POST", "/api/auth/google", { id_token: "g-only-tok" });
      assert.equal(gRes.status, 200);
      assert.equal(gRes.body.user.has_password, false);

      const otpRes = await request("POST", "/api/auth/send-otp", {
        email: "google.user@student.unud.ac.id",
        purpose: "register",
      });
      assert.equal(otpRes.status, 409);
      assert.match(otpRes.body.error, /Google/);
    });

    it("supports bidirectional Google <-> Email login and atomic complete-onboarding", async () => {
      // 1. Brand-new Google user starts with has_password: false, profile_completed: false
      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "g-onboard-1",
          email: "Onboard.Google@student.unud.ac.id",
          email_verified: true,
          name: "Onboard Google",
          picture: "https://lh3.googleusercontent.com/a/onboard",
        }),
      }));
      const gNew = await request("POST", "/api/auth/google", { id_token: "g-onboard-tok" });
      assert.equal(gNew.status, 200);
      assert.equal(gNew.body.user.has_password, false);
      assert.equal(gNew.body.user.profile_completed, false);
      const googleUserId = gNew.body.user.id;
      const gHeaders = { Authorization: `Bearer ${gNew.body.access_token}` };

      // Missing prodi/angkatan/new_password rejected with 400
      const badOnboard = await request(
        "POST",
        "/api/auth/complete-onboarding",
        { full_name: "Onboard Google", prodi: "", angkatan: "2024", new_password: "123" },
        gHeaders
      );
      assert.equal(badOnboard.status, 400);

      // Logged-out session cannot complete onboarding
      await request("POST", "/api/auth/logout", { refresh_token: gNew.body.refresh_token });
      const loggedOutOnboard = await request(
        "POST",
        "/api/auth/complete-onboarding",
        { full_name: "Onboard Google", prodi: "Informatika", angkatan: "2024", new_password: "Password123" },
        gHeaders
      );
      assert.equal(loggedOutOnboard.status, 401);

      // Re-login with Google and complete onboarding atomically
      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "g-onboard-1",
          email: "Onboard.Google@student.unud.ac.id",
          email_verified: true,
          name: "Onboard Google",
          picture: "https://lh3.googleusercontent.com/a/onboard",
        }),
      }));
      const gActive = await request("POST", "/api/auth/google", { id_token: "g-onboard-tok-2" });
      assert.equal(gActive.status, 200);

      const onboardRes = await request(
        "POST",
        "/api/auth/complete-onboarding",
        {
          full_name: "Onboard Alumni",
          prodi: "Informatika",
          angkatan: "2024",
          kota: "Denpasar",
          pekerjaan: "Software Engineer",
          perusahaan: "PT Bali Tech",
          new_password: "GoogleEmailPass1",
        },
        { Authorization: `Bearer ${gActive.body.access_token}` }
      );
      assert.equal(onboardRes.status, 200);
      assert.equal(onboardRes.body.has_password, true);
      assert.equal(onboardRes.body.profile_completed, true);
      assert.equal(onboardRes.body.user.id, googleUserId);
      assert.equal(onboardRes.body.user.avatar_url, "https://lh3.googleusercontent.com/a/onboard");
      assert.equal(onboardRes.body.user.prodi, "Informatika");
      assert.equal(onboardRes.body.user.angkatan, "2024");
      assert.equal(onboardRes.body.user.kota, "Denpasar");
      assert.equal(onboardRes.body.user.pekerjaan, "Software Engineer");
      assert.equal(onboardRes.body.user.perusahaan, "PT Bali Tech");

      // 2. Google-created user logs in directly with Email + Password -> exact same account
      const emailLogin = await request("POST", "/api/auth/login", {
        email: "onboard.google@student.unud.ac.id",
        password: "GoogleEmailPass1",
      });
      assert.equal(emailLogin.status, 200);
      assert.equal(emailLogin.body.user.id, googleUserId);
      assert.equal(emailLogin.body.user.has_password, true);
      assert.equal(emailLogin.body.user.profile_completed, true);
      assert.equal(emailLogin.body.user.full_name, "Onboard Alumni");
      assert.equal(emailLogin.body.user.prodi, "Informatika");
      assert.equal(emailLogin.body.user.angkatan, "2024");
      assert.equal(emailLogin.body.user.kota, "Denpasar");
      assert.equal(emailLogin.body.user.avatar_url, "https://lh3.googleusercontent.com/a/onboard");

      // 3. Email-registered user logs in via Google (even with mixed-case email) -> exact same account
      const regOtp = await request("POST", "/api/auth/send-otp", {
        email: "Email.First@student.unud.ac.id",
        purpose: "register",
      });
      assert.equal(regOtp.status, 200);
      const regRes = await request("POST", "/api/auth/register", {
        email: "Email.First@student.unud.ac.id",
        password: "EmailFirstPass1",
        full_name: "Email First User",
        prodi: "Sistem Informasi",
        angkatan: "2022",
        kota: "Badung",
        otp: regOtp.body.dev_otp,
        otp_token: regOtp.body.otp_token,
      });
      assert.equal(regRes.status, 201);
      assert.equal(regRes.body.user.profile_completed, true);
      const emailUserId = regRes.body.user.id;

      googleMock.mock.mockImplementationOnce(async () => ({
        getPayload: () => ({
          sub: "g-linked-email-first",
          email: "EMAIL.FIRST@student.unud.ac.id",
          email_verified: true,
          name: "Ignored Google Name",
          picture: "https://lh3.googleusercontent.com/a/email-first",
        }),
      }));
      const linkedGoogle = await request("POST", "/api/auth/google", { id_token: "link-email-first-tok" });
      assert.equal(linkedGoogle.status, 200);
      assert.equal(linkedGoogle.body.user.id, emailUserId);
      assert.equal(linkedGoogle.body.user.has_password, true);
      assert.equal(linkedGoogle.body.user.profile_completed, true);
      assert.equal(linkedGoogle.body.user.full_name, "Email First User");
      assert.equal(linkedGoogle.body.user.prodi, "Sistem Informasi");
      assert.equal(linkedGoogle.body.user.angkatan, "2022");
      assert.equal(linkedGoogle.body.user.kota, "Badung");

      // Both Email and Google logins continue working for the linked account
      const emailAgain = await request("POST", "/api/auth/login", {
        email: "email.first@student.unud.ac.id",
        password: "EmailFirstPass1",
      });
      assert.equal(emailAgain.status, 200);
      assert.equal(emailAgain.body.user.id, emailUserId);

      // 4. Legacy user with password already set but incomplete profile completes profile without new_password
      const legacyId = crypto.randomUUID();
      const legacyHash = await require("bcryptjs").hash("LegacyPass123", 4);
      db.tables.users.push({
        id: legacyId,
        email: "legacy.noprofile@unud.ac.id",
        password_hash: legacyHash,
        role: "alumni",
        google_sub: "g-legacy-1",
      });
      db.tables.user_profiles.push({
        id: crypto.randomUUID(),
        user_id: legacyId,
        full_name: "Legacy Google User",
        avatar_url: null,
        prodi: null,
        angkatan: null,
      });

      const legacyLogin = await request("POST", "/api/auth/login", {
        email: "legacy.noprofile@unud.ac.id",
        password: "LegacyPass123",
      });
      assert.equal(legacyLogin.status, 200);
      assert.equal(legacyLogin.body.user.has_password, true);
      assert.equal(legacyLogin.body.user.profile_completed, false);

      // Sending new_password when password already exists must return 400
      const rejectPw = await request(
        "POST",
        "/api/auth/complete-onboarding",
        { full_name: "Legacy Google User", prodi: "Elektro", angkatan: "2020", new_password: "NewPassword1" },
        { Authorization: `Bearer ${legacyLogin.body.access_token}` }
      );
      assert.equal(rejectPw.status, 400);

      // Completing profile without new_password succeeds
      const legacyDone = await request(
        "POST",
        "/api/auth/complete-onboarding",
        { full_name: "Legacy Google User", prodi: "Elektro", angkatan: "2020" },
        { Authorization: `Bearer ${legacyLogin.body.access_token}` }
      );
      assert.equal(legacyDone.status, 200);
      assert.equal(legacyDone.body.has_password, true);
      assert.equal(legacyDone.body.profile_completed, true);
      assert.equal(legacyDone.body.user.prodi, "Elektro");
      assert.equal(legacyDone.body.user.angkatan, "2020");
    });
  });
});
