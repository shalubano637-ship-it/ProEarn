-- Google Sign-In first-time profile onboarding.
-- Existing profiles are treated as complete so returning users are not interrupted.
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS "profileSetupCompleted" boolean NOT NULL DEFAULT true;

UPDATE public.users
SET "profileSetupCompleted" = true
WHERE "profileSetupCompleted" IS NULL;

ALTER TABLE public.users
  ALTER COLUMN "profileSetupCompleted" SET DEFAULT true,
  ALTER COLUMN "profileSetupCompleted" SET NOT NULL;
