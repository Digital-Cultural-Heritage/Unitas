-- 004_add_comment_replies.sql
-- Add parent_id to post_comments for Instagram-style nested replies

ALTER TABLE post_comments
  ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES post_comments(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_post_comments_parent_id
  ON post_comments(parent_id);

NOTIFY pgrst, 'reload schema';
