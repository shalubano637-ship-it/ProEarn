# Supabase and Cloudflare deployment checklist

These settings are required before the external account-deletion page and the
server-side media moderation changes can work in production.

## Firebase email verification for the public deletion page

The public page at
`https://prosn.in/policy/account-deletion.html` authenticates the account
owner with Firebase Email/Password. Every website deletion request must call
Firebase Authentication's `accounts:sendOobCode` endpoint with
`requestType: VERIFY_EMAIL`. Do not skip this send merely because a previous
lookup reports `emailVerified=true`.

The page must keep the permanent-delete form hidden until the user opens the
Firebase verification email and returns to the page. On return, it must refresh
the account using Firebase `accounts:lookup` and require
`emailVerified=true`.

Firebase setup checklist:

- Add `prosn.in` under Firebase Console → Authentication → Settings →
  Authorized domains.
- Keep the Email/Password provider enabled.
- Configure the Firebase Authentication email verification template and
  confirm that the action link can return to the supplied continue URL.
- Check Inbox and Spam/Junk when testing delivery.

The public page loads the browser-safe Firebase API key from the committed
Android `google-services.json` and the Supabase publishable key from
`lib/main.dart`. These are public client configuration values; never put a
Firebase service-account private key or Supabase service-role key in the page.

## Edge Functions

The deployed account-deletion functions validate Firebase ID tokens with the
Firebase Admin SDK. For both `delete-account` and
`delete-account-request`, the Supabase gateway setting is intentionally
`verify_jwt=false` because these endpoints perform their own Firebase token
verification in the function using
`verifyIdToken(token, true)`. Do not remove the in-function verification or
change these two endpoints to trust a request merely because it has a Bearer
header.

The request function checks the Firebase user is active, has an email, and
has `emailVerified=true`. The direct deletion function independently repeats
the active-user and verified-email checks before deleting any app data or
media. This second check prevents callers from bypassing the request endpoint.

The Firebase Admin service-account JSON must be configured in Supabase Edge
Function Secrets as `FIREBASE_SERVICE_ACCOUNT_JSON`, with project ID
`proearn-6acdd`.

The two account-deletion functions also require:
`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and
`SUPABASE_ANON_KEY`. The deletion and moderation functions need
`MEDIA_GATEWAY_URL`, `MEDIA_INTERNAL_TOKEN`, and `R2_PUBLIC_URL` (the same
public R2 base URL used by `r2-upload`).

Deploy the account-deletion functions to project
`mltvpfqfhbhgkejcjpmq` after updating their source:

```bash
supabase functions deploy delete-account --project-ref mltvpfqfhbhgkejcjpmq --no-verify-jwt
supabase functions deploy delete-account-request --project-ref mltvpfqfhbhgkejcjpmq --no-verify-jwt
```

Other functions must retain their own auth setting and must not be changed as
part of this account-deletion flow.

## Cloudflare media gateway

Deploy the updated `cloudflare/media-gateway/worker.ts` to the same Worker
referenced by `MEDIA_GATEWAY_URL`.

Set the Worker secret `INTERNAL_DELETE_TOKEN` to exactly the same secret value
as Supabase Edge Function secret `MEDIA_INTERNAL_TOKEN`. Do not put either
value in GitHub or in the Flutter app.

Verify that `MEDIA_GATEWAY_URL` points to that deployed Worker. Account
deletion intentionally stops before deleting the Auth account if R2 cleanup
fails, so the user can retry.

## ImgBB legacy media limitation

ImgBB's documented API exposes an upload endpoint and returns a
`delete_url`, but it does not document a server-side delete API. Existing
legacy ImgBB images therefore cannot be guaranteed to disappear automatically
through this account-deletion function. New current-app uploads use R2. See
the privacy policy disclosure and arrange provider-side cleanup for legacy
images where required.
