const supabase = require("./supabase");

/**
 * Create an in-app notification safely without failing the main request.
 * Skips creating a notification if the actor is the same as the recipient.
 */
async function createNotification({
  userId,
  actorId = null,
  type,
  title,
  body = null,
  referenceId = null,
}) {
  if (!userId || (actorId && userId === actorId)) return;
  try {
    const safeTitle = typeof title === "string" ? title.slice(0, 200) : String(title || "").slice(0, 200);
    const safeBody = typeof body === "string" && body.trim() ? body.trim().slice(0, 500) : null;

    const { error } = await supabase.from("notifications").insert({
      user_id: userId,
      actor_id: actorId,
      type,
      title: safeTitle,
      body: safeBody,
      reference_id: referenceId ? String(referenceId) : null,
    });
    if (error) {
      console.error("Failed to create notification:", error.message);
    }
  } catch (err) {
    console.error("Failed to create notification:", err.message);
  }
}

module.exports = { createNotification };
