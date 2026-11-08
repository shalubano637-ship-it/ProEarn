# Supabase and Cloudflare deployment checklist

These settings are required before the external account-deletion page and the
server-side media moderation changes can work in production.

## Supabase Auth email template

The public deletion page asks the account owner to enter an email OTP. In the
Supabase Dashboard, open **Authentication → Email Templates** and ensure the
email sign-in template sends the numeric token using `{{ .Token }}`. A template
that only sends a confirmation URL will not provide a code for the page's OTP
input.

## Edge Functions

After merging the code, deploy these functions to project
`mltvpfqfhbhgkejcjpmq`:

- `delete-account` with JWT verification enabled.
- `delete-account-request` with JWT verification enabled.
- `r2-upload` with JWT verification enabled.
- `imgbb-upload` with JWT verification enabled (legacy client path; all image
  folders are now moderated).

From the repository root, deploy the functions after merging:

```bash
supabase functions deploy delete-account --project-ref mltvpfqfhbhgkejcjpmq
supabase functions deploy delete-account-request --project-ref mltvpfqfhbhgkejcjpmq
supabase functions deploy admin-moderate-report --project-ref mltvpfqfhbhgkejcjpmq
supabase functions deploy r2-upload --project-ref mltvpfqfhbhgkejcjpmq
supabase functions deploy imgbb-upload --project-ref mltvpfqfhbhgkejcjpmq
```

Keep JWT verification enabled for all four functions. The public deletion page
obtains a Supabase Auth session before invoking the request function.

The account deletion and admin moderation functions need `MEDIA_GATEWAY_URL`, `MEDIA_INTERNAL_TOKEN`, and `R2_PUBLIC_URL` (the same public R2 base URL used by `r2-upload`).

The account deletion functions must have the standard Supabase environment
variables available: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY`.

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
