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

function isEmailDeliveryConfigured() {
  const cfg = getSmtpConfig();
  return Boolean((cfg.host && cfg.user && cfg.pass) || (process.env.RESEND_API_KEY || "").trim());
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
    requireTLS: !cfg.secure,
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

function purposeCopy(purpose, otpCode) {
  switch (purpose) {
    case "register":
      return {
        subject: `${otpCode} adalah kode verifikasi Unitas Anda`,
        heading: "Verifikasi Email Kampus",
        actionText: "melengkapi pendaftaran akun Unitas Anda",
      };
    case "reset":
      return {
        subject: `${otpCode} adalah kode reset kata sandi Unitas Anda`,
        heading: "Reset Kata Sandi Unitas",
        actionText: "mengatur ulang kata sandi akun Unitas Anda",
      };
    case "login":
    default:
      return {
        subject: `${otpCode} adalah kode masuk Unitas Anda`,
        heading: "Verifikasi Masuk Unitas",
        actionText: "masuk ke akun Unitas Anda",
      };
  }
}

function extractEmailAddress(raw) {
  const m = String(raw || "").match(/<([^>]+)>/);
  if (m && m[1]) return m[1].trim();
  const trimmed = String(raw || "").trim();
  return trimmed.includes("@") ? trimmed : "";
}

function extractDisplayName(raw) {
  const str = String(raw || "").trim();
  const angleIdx = str.indexOf("<");
  if (angleIdx > 0) {
    const name = str.slice(0, angleIdx).trim().replace(/^["']|["']$/g, "");
    if (name && !/no-?reply/i.test(name)) return name;
  }
  return "Unitas";
}

function resolveSenderAddresses(cfg) {
  const rawFrom = (process.env.EMAIL_FROM || "").trim();
  const displayName = extractDisplayName(rawFrom);
  const isGmailSmtp = Boolean(cfg.host.toLowerCase().includes("gmail.com") && cfg.user);

  let from;
  if (isGmailSmtp) {
    from = `${displayName} <${cfg.user}>`;
  } else if (rawFrom) {
    from = rawFrom;
  } else {
    from = cfg.user ? `${displayName} <${cfg.user}>` : "Unitas <noreply@unud.ac.id>";
  }

  const rawReplyTo = (process.env.EMAIL_REPLY_TO || "").trim();
  const replyTo = rawReplyTo || cfg.user || extractEmailAddress(from) || "noreply@unud.ac.id";
  return { from, replyTo };
}

async function sendOtpEmail({ to, otpCode, purpose = "login" }) {
  const cfg = getSmtpConfig();
  const { from, replyTo } = resolveSenderAddresses(cfg);
  const copy = purposeCopy(purpose, otpCode);
  const safeCode = escapeHtml(otpCode);
  const preheaderText = `Kode verifikasi Unitas Anda: ${otpCode} (berlaku 15 menit).`;

  const text = [
    preheaderText,
    "",
    copy.heading,
    `Gunakan kode 6 digit di atas untuk ${copy.actionText}.`,
    "",
    "Demi keamanan, jangan bagikan kode ini kepada siapa pun.",
    "Jika Anda tidak meminta kode ini, silakan abaikan email ini.",
    "",
    "Salam,",
    "Tim Unitas",
  ].join("\n");

  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px; background: #FDFBF7; border: 1px solid #E5E7EB; border-radius: 12px; color: #1E293B;">
      <span style="display: none; max-height: 0; overflow: hidden; opacity: 0; mso-hide: all;">${escapeHtml(preheaderText)}</span>
      <p style="margin: 0 0 12px; font-size: 18px; font-weight: 700; color: #1E3A5F;">Unitas</p>
      <p style="margin: 0 0 8px; font-size: 16px; font-weight: 600; color: #1E3A5F;">${escapeHtml(copy.heading)}</p>
      <p style="margin: 0 0 16px; font-size: 14px; line-height: 1.5; color: #334155;">
        Gunakan kode 6 digit berikut untuk ${escapeHtml(copy.actionText)}:
      </p>
      <div style="background: #F5F2EC; border: 1px solid #E2E8F0; color: #1E3A5F; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 28px; font-weight: 700; letter-spacing: 6px; text-align: center; padding: 14px 20px; border-radius: 10px; margin-bottom: 16px;">
        ${safeCode}
      </div>
      <p style="margin: 0 0 8px; font-size: 13px; line-height: 1.5; color: #475569;">
        Kode ini berlaku selama <strong>15 menit</strong>. Demi keamanan, jangan bagikan kode ini kepada siapa pun.
      </p>
      <p style="margin: 0 0 16px; font-size: 13px; line-height: 1.5; color: #475569;">
        Jika Anda tidak meminta kode ini, silakan abaikan email ini.
      </p>
      <p style="margin: 0; font-size: 13px; color: #475569;">
        Salam,<br />Tim Unitas
      </p>
    </div>
  `.trim();

  if (cfg.host && cfg.user && cfg.pass) {
    const transporter = getTransporter(cfg);
    const info = await transporter.sendMail({
      from,
      to,
      replyTo,
      subject: copy.subject,
      text,
      html,
    });
    if (Array.isArray(info?.rejected) && info.rejected.length > 0) {
      throw new Error(`SMTP rejected recipient: ${info.rejected.join(", ")}`);
    }
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
        reply_to: replyTo,
        subject: copy.subject,
        text,
        html,
      }),
      signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) {
      const errText = await r.text().catch(() => "");
      throw new Error(`Resend HTTP ${r.status}${errText ? `: ${errText.slice(0, 200)}` : ""}`);
    }
    return { sent: true, provider: "resend" };
  }

  if (process.env.NODE_ENV !== "production") {
    console.log(`[Unitas OTP] (${purpose}) ${to}: ${otpCode}`);
  }
  return { sent: false, provider: "console" };
}

module.exports = { sendOtpEmail, isEmailDeliveryConfigured };
