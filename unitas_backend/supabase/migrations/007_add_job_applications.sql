-- 007_add_job_applications.sql
-- Tabel lamaran kerja alumni + bucket storage CV (maks 1 MB PDF)

CREATE TABLE IF NOT EXISTS public.job_applications (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id       UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
  applicant_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  cv_url       TEXT NOT NULL,
  cover_note   TEXT,
  status       TEXT NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending', 'reviewed', 'referred', 'rejected')),
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(job_id, applicant_id)
);

CREATE INDEX IF NOT EXISTS idx_job_applications_job
  ON public.job_applications(job_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_job_applications_applicant
  ON public.job_applications(applicant_id, created_at DESC);

CREATE OR REPLACE TRIGGER trg_job_applications_updated_at
  BEFORE UPDATE ON public.job_applications
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.job_applications ENABLE ROW LEVEL SECURITY;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('cvs', 'cvs', true, 1048576, ARRAY['application/pdf'])
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;
