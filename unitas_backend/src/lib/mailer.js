const nodemailer = require("nodemailer");

let cachedTransport = null;
let cachedTransportKey = "";

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function getSmtpConfig() {
  const host = (process.env.SMTP_HOST || "").trim();
  const port = Number(process.env.SMTP_PORT) || 587;
  const secure = process.env.SMTP_SECURE === "true" || port === 465;
  const user = (process.env.SMTP_USER || "").trim();
  const pass = process.env.SMTP_PASS || "";
  return { host, port, secure, user, pass };
}

function getTransporter(cfg) {
  const key = `${cfg.host}|${cfg.port}|${cfg.secure}|${cfg.user}|${cfg.pass}`;
  if (cachedTransport && cachedTransportKey === key) {
    return cachedTransport;
  }
  cachedTransport = nodemailer.createTransport({
    host: cfg.host,
    port: cfg.port,
    secure: cfg.secure,
    auth: {
      user: cfg.user,
      pass: cfg.pass,
    },
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 15000,
  });
  cachedTransportKey = key;
  return cachedTransport;
}

function purposeCopy(purpose) {
  switch (purpose) {
    case "register":
      return {
        subject: "Kode Verifikasi Pendaftaran Unitas",
        heading: "Verifikasi Email Kampus",
        actionText: "melengkapi pendaftaran akun Unitas Anda",
      };
    case "reset":
      return {
        subject: "Kode Reset Kata Sandi Unitas",
        heading: "Reset Kata Sandi",
        actionText: "mengatur ulang kata sandi akun Unitas Anda",
      };
    case "login":
    default:
      return {
        subject: "Kode OTP Masuk Unitas",
        heading: "Verifikasi Login Unitas",
        actionText: "masuk ke akun Unitas Anda",
      };
  }
}

async function sendOtpEmail({ to, otpCode, purpose = "login" }) {
  const cfg = getSmtpConfig();
  const from =
    (process.env.EMAIL_FROM || "").trim() ||
    (cfg.user ? `Unitas No-Reply <${cfg.user}>` : "Unitas No-Reply <noreply@unud.ac.id>");
  const copy = purposeCopy(purpose);
  const safeCode = escapeHtml(otpCode);

  const text = [
    `${copy.heading} - Unitas`,
    "",
    `Gunakan kode OTP berikut untuk ${copy.actionText}:`,
    "",
    `    ${otpCode}`,
    "",
    "Kode ini berlaku selama 15 menit. Jangan bagikan kode ini kepada siapa pun.",
    "",
    "Ini adalah email otomatis (no-reply), mohon tidak membalas email ini.",
  ].join("\n");

  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px; background: #FDFBF7; border: 1px solid #E5E7EB; border-radius: 12px; color: #1E293B;">
      <div style="margin-bottom: 16px;">
        <strong style="font-size: 20px; color: #1E3A5F;">Unitas</strong>
      </div>
      <h2 style="margin: 0 0 8px; font-size: 18px; color: #1E3A5F;">${escapeHtml(copy.heading)}</h2>
      <p style="margin: 0 0 20px; font-size: 14px; line-height: 1.5;">
        Gunakan kode OTP 6 digit berikut untuk ${escapeHtml(copy.actionText)}:
      </p>
      <div style="background: #1E3A5F; color: #FFFFFF; font-size: 28px; font-weight: 700; letter-spacing: 6px; text-align: center; padding: 14px 20px; border-radius: 10px; margin-bottom: 20px;">
        ${safeCode}
      </div>
      <p style="margin: 0 0 12px; font-size: 13px; color: #475569;">
        Kode ini berlaku selama <strong>15 menit</strong>. Demi keamanan, jangan bagikan kode ini kepada siapa pun.
      </p>
      <hr style="border: none; border-top: 1px solid #E2E8F0; margin: 16px 0;" />
      <p style="margin: 0; font-size: 12px; color: #64748B;">
        Ini adalah email otomatis (no-reply), mohon tidak membalas email ini.
      </p>
    </div>
  `.trim();

  if (cfg.host && cfg.user && cfg.pass) {
    const transporter = getTransporter(cfg);
    await transporter.sendMail({
      from,
      to,
      replyTo: "noreply@unud.ac.id",
      subject: copy.subject,
      text,
      html,
    });
    return { sent: true, provider: "smtp" };
  }

  if (process.env.RESEND_API_KEY) {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [to],
        reply_to: "noreply@unud.ac.id",
        subject: copy.subject,
        text,
        html,
      }),
      signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) {
      throw new Error(`Resend HTTP ${r.status}`);
    }
    return { sent: true, provider: "resend" };
  }

  if (process.env.NODE_ENV !== "production") {
    console.log(`[Unitas OTP] (${purpose}) ${to}: ${otpCode}`);
  }
  return { sent: false, provider: "console" };
}

module.exports = { sendOtpEmail };
