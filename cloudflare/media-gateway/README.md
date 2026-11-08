# ProEarn Cloudflare media gateway

The Worker provides:
- Authenticated image moderation through Workers AI.
- Internal per-user R2 cleanup during account deletion.

New image uploads are handled by the Supabase `r2-upload` Edge Function. That function uses the R2 credentials stored as Supabase Edge Function secrets and writes objects to the `proearn-videos` bucket.

Required Worker binding:
- `R2_BUCKET` -> `proearn-videos`

Required Worker variables/secrets:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `INTERNAL_DELETE_TOKEN`
- `MODERATION_SHARED_SECRET`

The Worker fails closed if server moderation is unavailable.
