# ProEarn Cloudflare media gateway

Flow:
1. Flutter performs on-device moderation.
2. Flutter requests /v1/upload-intent with the Supabase access token.
3. Worker authenticates the user and returns a short-lived R2 PUT URL.
4. Flutter uploads directly to R2.
5. Flutter calls /v1/finalize-post or /v1/finalize-media.
6. Worker fetches the object and performs a server-side vision safety check with Cloudflare Workers AI.
7. Only approved posts are inserted into Supabase with the service-role key.

Required Cloudflare secrets:
- R2_ACCESS_KEY_ID
- R2_SECRET_ACCESS_KEY
- SUPABASE_SERVICE_ROLE_KEY

Required variables:
- R2_ACCOUNT_ID
- R2_PUBLIC_BASE_URL
- SUPABASE_URL
- SUPABASE_ANON_KEY

The Worker fails closed if server moderation is unavailable.
