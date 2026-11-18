-- 006_indexes_and_fixes.sql
-- Query performance indexes, safe comment counter trigger, and increment_points RPC

-- ============================================================
-- 1. Missing indexes for hot queries
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_post_comments_post_created
  ON post_comments(post_id, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_events_category_date
  ON events(category, event_date ASC);

CREATE INDEX IF NOT EXISTS idx_events_creator_date
  ON events(creator_id, event_date DESC);

CREATE INDEX IF NOT EXISTS idx_event_registrations_event_reg
  ON event_registrations(event_id, registered_at DESC);

CREATE INDEX IF NOT EXISTS idx_event_registrations_user
  ON event_registrations(user_id);

CREATE INDEX IF NOT EXISTS idx_jobs_active_created
  ON jobs(created_at DESC)
  WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_jobs_poster_created
  ON jobs(poster_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_saved_jobs_user_saved
  ON saved_jobs(user_id, saved_at DESC);

CREATE INDEX IF NOT EXISTS idx_connections_addressee_status
  ON alumni_connections(addressee_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_connections_requester_status
  ON alumni_connections(requester_id, status);

CREATE INDEX IF NOT EXISTS idx_messages_sender_created
  ON messages(sender_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_receiver_created
  ON messages(receiver_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON notifications(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_profiles_kota_pts
  ON user_profiles(kota, points DESC);

CREATE INDEX IF NOT EXISTS idx_user_profiles_prodi_pts
  ON user_profiles(prodi, points DESC);

CREATE INDEX IF NOT EXISTS idx_user_profiles_online_pts
  ON user_profiles(points DESC)
  WHERE is_online = TRUE;

-- ============================================================
-- 2. Prevent negative comments_count on comment deletion
-- ============================================================
CREATE OR REPLACE FUNCTION update_post_comments_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE posts SET comments_count = GREATEST(comments_count - 1, 0) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 3. Atomic points increment RPC used by posts/comments routes
-- ============================================================
CREATE OR REPLACE FUNCTION increment_points(uid UUID, pts INTEGER)
RETURNS VOID AS $$
BEGIN
  UPDATE user_profiles
  SET points = COALESCE(points, 0) + GREATEST(pts, 0)
  WHERE user_id = uid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

NOTIFY pgrst, 'reload schema';
