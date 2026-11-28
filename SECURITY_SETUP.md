# Pro Earn — full security migration setup

Sensitive server-side operations are kept behind Supabase Edge Functions. The app itself no longer
holds any credential — nothing to recover by decompiling the APK/IPA.

| Operation / credential                    | Current server-side handling  |
|--------------------------------------------|---------------------------------|
| Cloudflare R2 credentials                  | `r2-upload` function            |
| Gmail App Password + client OTP compare     | `send-otp` + `verify-otp`       |
| OneSignal REST API key                      | `notify` function               |
| Google Vision API key                       | `check-image-safety` function   |

Image uploads use **Cloudflare R2**. The Flutter app sends image bytes to the `r2-upload` Edge Function using a Firebase ID token. The function verifies the identity, calls the Cloudflare media gateway for server-side moderation, and stores approved media in the configured R2 bucket. R2 credentials remain server-side in Supabase Edge Function secrets.

Plus database-level fixes in `supabase_schema.sql` (see the
"SECURITY HARDENING" section at the bottom) that close a few RLS gaps a
modified client could otherwise hit directly:
- Any signed-in user could previously edit **any** post, not just their own.
- Any signed-in user could insert a fake notification addressed to anyone.
- Sensitive columns (`isEmailVerified`, `totalGets`, `followers`, etc.)
  could be set directly by the row's own owner via a raw PATCH.

## 1. Run the schema update
Open the Supabase SQL editor and run all of `supabase_schema.sql` top to
bottom (safe to re-run — everything uses `if not exists` / `or replace`).

## 2. Deploy the edge functions
```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase functions deploy r2-upload
supabase functions deploy send-otp
supabase functions deploy verify-otp
supabase functions deploy notify
supabase functions deploy check-image-safety
```

## 3. Set the secrets
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
injected automatically. Everything else:

```bash
supabase secrets set \
  GMAIL_SENDER_EMAIL=proearn.in@gmail.com \
  GMAIL_APP_PASSWORD=<new-gmail-app-password> \
  ONESIGNAL_APP_ID=09286c92-4d17-4f28-9953-dc5fd19f5683 \
  ONESIGNAL_REST_API_KEY=<new-onesignal-rest-key> \
  GOOGLE_VISION_API_KEY=<new-google-vision-key>
```

## 4. Rotate every key that was previously hardcoded
These were already burned the moment they shipped inside a compiled
app — anyone who had installed the app could extract them. Generate
fresh ones and use *those* above:
- **Legacy media-host credential**: any credential previously embedded in client code or documentation should be revoked at its original provider. The current app upload path does not use it.
- **Gmail App Password**: Google Account → Security → App passwords →
  revoke the old one, create a new one.
- **OneSignal REST API key**: OneSignal dashboard → Settings → Keys &
  IDs → regenerate.
- **Google Vision API key**: Google Cloud Console → Credentials →
  delete the old key, create a new one restricted to the Vision API.

## Current image upload flow

- `lib/service.dart` routes app image uploads through `CloudflareMediaService`.
- `lib/cloudflare_media_service.dart` sends the image bytes to the Supabase `r2-upload` Edge Function with a Firebase ID token.
- `supabase/functions/r2-upload/index.ts` verifies the Firebase identity, requires successful server-side image moderation through the Cloudflare media gateway, and stores the image in Cloudflare R2.
- The client contains no R2 access key or secret. The live upload function does not require a third-party image-host API key.

## Note on image moderation

The current `r2-upload` function enforces moderation server-side before storage for every supported image category. The Cloudflare media gateway performs the moderation check; the upload function fails closed if moderation rejects the image or the moderation service is unavailable. Keep the gateway URL and internal authorization configured only on the server.
