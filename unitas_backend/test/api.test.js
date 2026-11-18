const { describe, it, before, after } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");

// Ensure required env vars exist for module initialization in test
process.env.SUPABASE_URL = process.env.SUPABASE_URL || "https://example.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "test-service-key";
process.env.JWT_SECRET = process.env.JWT_SECRET || "test-jwt-secret-123456";
process.env.REFRESH_TOKEN_SECRET = process.env.REFRESH_TOKEN_SECRET || "test-refresh-secret-123456";

const app = require("../api/index");

let server;
let baseUrl;

function request(method, path, body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, baseUrl);
    const payload = body ? JSON.stringify(body) : null;
    const req = http.request(
      url,
      {
        method,
        headers: {
          ...(payload ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) } : {}),
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
    if (payload) req.write(payload);
    req.end();
  });
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

  it("POST /api/auth/login validates empty body with 400", async () => {
    const res = await request("POST", "/api/auth/login", {});
    assert.equal(res.status, 400);
  });

  it("POST /api/auth/register validates short password with 400", async () => {
    const res = await request("POST", "/api/auth/register", {
      email: "user@example.com",
      password: "123",
      full_name: "Test User",
      prodi: "Informatika",
      angkatan: "2022",
    });
    assert.equal(res.status, 400);
  });

  it("Protected endpoints reject unauthenticated requests with 401", async () => {
    const [postsRes, notifRes, msgRes, jobsRes] = await Promise.all([
      request("POST", "/api/posts", { content: "Halo" }),
      request("GET", "/api/notifications"),
      request("GET", "/api/messages/conversations"),
      request("GET", "/api/jobs/my-jobs/all"),
    ]);
    assert.equal(postsRes.status, 401);
    assert.equal(notifRes.status, 401);
    assert.equal(msgRes.status, 401);
    assert.equal(jobsRes.status, 401);
  });
});
