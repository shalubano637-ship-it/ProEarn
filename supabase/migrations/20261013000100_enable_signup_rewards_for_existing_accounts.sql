-- Enable the signup rewards popup for every existing account.
-- New accounts continue to use the column default and existing claim checks remain idempotent.
SELECT set_config('app.bypass_column_protection', 'on', true);

UPDATE public.users
SET "signupRewardEligible" = TRUE,
    "signupRewardStartedAt" = CASE
      WHEN "firstLoginRewardClaimedAt" IS NOT NULL AND "signupRewardStartedAt" IS NULL
        THEN now()
      ELSE "signupRewardStartedAt"
    END;
