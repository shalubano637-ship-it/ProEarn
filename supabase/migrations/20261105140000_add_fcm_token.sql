-- Store the Android Firebase Cloud Messaging registration token per user.
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS "fcmToken" text;
