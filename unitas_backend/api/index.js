require("dotenv").config();
const express = require("express");
const cors = require("cors");
const { errorHandler } = require("../src/middleware/errorHandler");

// Routes
const authRoutes   = require("../src/routes/auth");
const usersRoutes  = require("../src/routes/users");
const postsRoutes  = require("../src/routes/posts");
const eventsRoutes = require("../src/routes/events");
const jobsRoutes   = require("../src/routes/jobs");
const uploadRoutes = require("../src/routes/upload");
const statsRoutes  = require("../src/routes/stats");

const app = express();

// ── Middleware ────────────────────────────────────────────────────────────
app.use(cors({
  origin: process.env.CORS_ORIGIN || "*",
  methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization"],
}));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

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

// ── API Routes ────────────────────────────────────────────────────────────
app.use("/api/auth",   authRoutes);
app.use("/api/users",  usersRoutes);
app.use("/api/posts",  postsRoutes);
app.use("/api/events", eventsRoutes);
app.use("/api/jobs",   jobsRoutes);
app.use("/api/upload", uploadRoutes);
app.use("/api/stats",  statsRoutes);

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
