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
    await supabase.from("notifications").insert({
      user_id: userId,
      actor_id: actorId,
      type,
      title,
      body,
      reference_id: referenceId ? String(referenceId) : null,
    });
  } catch (err) {
    console.error("Failed to create notification:", err.message);
  }
}

module.exports = { createNotification };
