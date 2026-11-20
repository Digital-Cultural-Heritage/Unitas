require("dotenv").config();
const express = require("express");
const cors = require("cors");
const { errorHandler } = require("../src/middleware/errorHandler");

const app = express();

app.disable("x-powered-by");
// Di Vercel ada 1 proxy di depan -> IP klien yang benar untuk rate limiting
if (process.env.VERCEL) app.set("trust proxy", 1);

// ── Middleware ────────────────────────────────────────────────────────────
// Auth memakai header Bearer (bukan cookie), jadi origin "*" aman secara default.
// Batasi dengan CORS_ORIGIN (pisahkan koma untuk beberapa origin) bila perlu.
const corsOrigin = (process.env.CORS_ORIGIN || "*").trim();
app.use(cors({
  origin: corsOrigin === "*" ? "*" : corsOrigin.split(",").map((s) => s.trim()).filter(Boolean),
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization"],
  maxAge: 86400,
}));
app.use(express.json({ limit: "100kb" }));
app.use(express.urlencoded({ extended: true, limit: "100kb" }));

// ── Health check ──────────────────────────────────────────────────────────
app.get("/", (req, res) => {
  res.json({
    name: "Unitas API",
    version: "1.0.0",
    status: "running",
    timestamp: new Date().toISOString(),
  });
});

app.get("/api/health", (req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

// Lazy-load tiap router agar cold start serverless tidak memuat dependensi berat,
// sambil tetap memakai literal require(...) agar bundler Vercel (@vercel/nft) menyertakan semua route.
function lazyRoute(loader) {
  let router;
  return (req, res, next) => {
    if (!router) router = loader();
    return router(req, res, next);
  };
}

// ── Cek konfigurasi wajib ─────────────────────────────────────────────────
const REQUIRED_ENV = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "JWT_SECRET", "REFRESH_TOKEN_SECRET"];
const missingEnv = REQUIRED_ENV.filter((k) => !process.env[k]);

if (missingEnv.length > 0) {
  // Jangan crash saat cold start: laporkan jelas di log, balas 503 generik ke klien
  console.error(`[Config] Environment variable belum diset: ${missingEnv.join(", ")}`);
  app.use("/api", (req, res) => {
    res.status(503).json({ error: "Server belum dikonfigurasi dengan benar" });
  });
} else {
  // ── API Routes ──────────────────────────────────────────────────────────
  app.use("/api/auth",          lazyRoute(() => require("../src/routes/auth")));
  app.use("/api/users",         lazyRoute(() => require("../src/routes/users")));
  app.use("/api/posts",         lazyRoute(() => require("../src/routes/posts")));
  app.use("/api/events",        lazyRoute(() => require("../src/routes/events")));
  app.use("/api/jobs",          lazyRoute(() => require("../src/routes/jobs")));
  app.use("/api/upload",        lazyRoute(() => require("../src/routes/upload")));
  app.use("/api/stats",         lazyRoute(() => require("../src/routes/stats")));
  app.use("/api/notifications", lazyRoute(() => require("../src/routes/notifications")));
  app.use("/api/keys",          lazyRoute(() => require("../src/routes/keys")));
  app.use("/api/messages",      lazyRoute(() => require("../src/routes/messages")));
}

// ── 404 handler ───────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: `Endpoint ${req.method} ${req.path} tidak ditemukan` });
});

// ── Global error handler ──────────────────────────────────────────────────
app.use(errorHandler);

// ── Local dev server ──────────────────────────────────────────────────────
if (require.main === module) {
  const PORT = process.env.PORT || 3000;
  app.listen(PORT, () => {
    console.log(`🚀 Unitas API berjalan di http://localhost:${PORT}`);
  });
}

// Vercel Serverless export
module.exports = app;
