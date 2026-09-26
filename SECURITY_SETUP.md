# Pro Earn — full security migration setup

Every hardcoded secret and every client-trusted value has been moved
server-side, into 6 Supabase Edge Functions. The app itself no longer
holds any credential — nothing to recover by decompiling the APK/IPA.

| Old (in the app)                          | Now (server-side)              |
|--------------------------------------------|---------------------------------|
| ImgBB API key hardcoded in app              | `imgbb-upload` function         |
| Gmail App Password + client OTP compare     | `send-otp` + `verify-otp`       |
| OneSignal REST API key                      | `notify` function               |
| Google Vision API key                       | `check-image-safety` function   |
| Client-computed payout amount               | `request-payout` function       |

Image uploads are back on **ImgBB** (Cloudflare R2 setup is on hold for
now) — but the ImgBB key lives only inside `imgbb-upload`. The app sends
the image as base64 to that function; the function does the actual
ImgBB upload and hands back the URL. Nothing to extract by decompiling.

Plus database-level fixes in `supabase_schema.sql` (see the
"SECURITY HARDENING" section at the bottom) that close a few RLS gaps a
modified client could otherwise hit directly:
- Any signed-in user could previously edit **any** post, not just their own.
- Any signed-in user could insert a fake notification addressed to anyone.
- Payout requests trusted whatever amount the client sent.
- Sensitive columns (`isEmailVerified`, `totalGets`, `followers`, etc.)
  could be set directly by the row's own owner via a raw PATCH.

## 1. Run the schema update
Open the Supabase SQL editor and run all of `supabase_schema.sql` top to
bottom (safe to re-run — everything uses `if not exists` / `or replace`).

## 2. Deploy the edge functions
```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase functions deploy imgbb-upload
supabase functions deploy send-otp
supabase functions deploy verify-otp
supabase functions deploy notify
supabase functions deploy check-image-safety
supabase functions deploy request-payout
```

## 3. Set the secrets
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
injected automatically. Everything else:

```bash
supabase secrets set \
  IMGBB_API_KEY=<new-imgbb-key> \
  GMAIL_SENDER_EMAIL=proearn.in@gmail.com \
  GMAIL_APP_PASSWORD=<new-gmail-app-password> \
  ONESIGNAL_APP_ID=09286c92-4d17-4f28-9953-dc5fd19f5683 \
  ONESIGNAL_REST_API_KEY=<new-onesignal-rest-key> \
  GOOGLE_VISION_API_KEY=<new-google-vision-key>
```

Getting an ImgBB key: [api.imgbb.com](https://api.imgbb.com/) → sign in
→ "Get API Key". Free tier is fine to start.

## 4. Rotate every key that was previously hardcoded
These were already burned the moment they shipped inside a compiled
app — anyone who had installed the app could extract them. Generate
fresh ones and use *those* above:
- **ImgBB key**: your old ImgBB key (`1f16f3c5205da4081486a76894cde105`)
  was hardcoded before — revoke/regenerate it on ImgBB, don't reuse it.
- **Gmail App Password**: Google Account → Security → App passwords →
  revoke the old one, create a new one.
- **OneSignal REST API key**: OneSignal dashboard → Settings → Keys &
  IDs → regenerate.
- **Google Vision API key**: Google Cloud Console → Credentials →
  delete the old key, create a new one restricted to the Vision API.

## What changed in the Flutter code
- `lib/service.dart`: `uploadImageToImgBB()` now calls the `imgbb-upload`
  edge function (base64 body) instead of hitting `api.imgbb.com`
  directly with a hardcoded key. `sendNotification()` / `isImageSafe()`
  call `notify` / `check-image-safety`. Added `requestCreatorOtp()`,
  `verifyCreatorOtp()`, `requestPayout()`.
- `lib/social_feed.dart`, `lib/user_profile_features.dart`: call sites
  unchanged (`uploadImageToImgBB(...)`), just calling the new secure
  implementation.
- `lib/main.dart`: OTP dialog calls `verifyCreatorOtp()`; withdrawal
  flow calls `requestPayout()`; removed the local Gmail SMTP sender and
  the `mailer` package dependency.
- `pubspec.yaml`: removed `mailer`.

## Switching to R2 later
When you're ready to set up Cloudflare R2, the earlier presigned-URL
approach (`r2-upload-url` edge function) can be dropped back in — it
was removed from this version, but the pattern is identical to the
other edge functions here. Just ask and I'll add it back alongside
ImgBB or as a replacement.

## Note on image moderation
`check-image-safety` stops the Vision key from being extracted from the
app, but a modified client could still skip calling it before
uploading. Fully closing that would need server-side enforcement at
insert time (bigger infra change) — ask if you want that too.
