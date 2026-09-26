// =============================================================================
// PRO EARN — imgbb-upload (Supabase Edge Function)
// -----------------------------------------------------------------------------
// Uploads an image to ImgBB on the app's behalf. The ImgBB API key lives
// only in this function's environment — it is never bundled inside the
// compiled app, so there's nothing to recover by decompiling the APK.
// The app sends the image as base64; this function does the actual
// multipart upload to ImgBB and returns the resulting public URL.
// =============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const IMGBB_API_KEY = Deno.env.get("IMGBB_API_KEY")!;

const MAX_BASE64_LENGTH = 12_000_000; // ~9MB decoded, generous ceiling for a compressed photo

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    // Require a logged-in Pro Earn user — no anonymous uploads through
    // (and no billing/quota abuse of) this function.
    const authHeader = req.headers.get("Authorization") ?? "";
    const authed = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: authError } = await authed.auth.getUser();
    if (authError || !userData?.user) return json({ error: "Unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const imageBase64 = String(body.imageBase64 ?? "");
    if (!imageBase64) return json({ error: "imageBase64 required" }, 400);
    if (imageBase64.length > MAX_BASE64_LENGTH) return json({ error: "Image too large" }, 400);

    const form = new FormData();
    form.append("image", imageBase64);

    const uploadResponse = await fetch(
      `https://api.imgbb.com/1/upload?key=${IMGBB_API_KEY}`,
      { method: "POST", body: form },
    );

    const data = await uploadResponse.json();
    if (!uploadResponse.ok || !data?.data?.url) {
      console.error("ImgBB upload failed:", uploadResponse.status, JSON.stringify(data));
      return json({ error: "Upload failed" }, 502);
    }

    return json({ url: data.data.url as string });
  } catch (e) {
    console.error("imgbb-upload error:", e);
    return json({ error: "Internal error" }, 500);
  }
});
