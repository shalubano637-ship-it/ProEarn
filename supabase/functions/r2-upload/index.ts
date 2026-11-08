import { createClient } from "npm:@supabase/supabase-js@2";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const R2_ACCOUNT_ID = Deno.env.get("R2_ACCOUNT_ID")!;
const R2_ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID")!;
const R2_SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY")!;
const R2_BUCKET_NAME = Deno.env.get("R2_BUCKET_NAME")!;
const R2_PUBLIC_URL = Deno.env.get("R2_PUBLIC_URL")!;
const MEDIA_GATEWAY_URL = Deno.env.get("MEDIA_GATEWAY_URL") ??
  "https://proearn-media-gateway.0nasir07860.workers.dev";

const MAX_BYTES = 9 * 1024 * 1024;
const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const ALLOWED_FOLDERS = new Set(["posts", "profile", "chat", "comments", "rooms"]);
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

function decodeBase64(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function extensionFor(contentType: string) {
  return contentType === "image/png" ? "png" : contentType === "image/webp" ? "webp" : "jpg";
}

function r2ObjectUrl(key: string) {
  const encodedKey = key.split("/").map(encodeURIComponent).join("/");
  return `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${R2_BUCKET_NAME}/${encodedKey}`;
}

const r2 = new AwsClient({
  accessKeyId: R2_ACCESS_KEY_ID,
  secretAccessKey: R2_SECRET_ACCESS_KEY,
  service: "s3",
  region: "auto",
});

async function putObject(key: string, bytes: Uint8Array, contentType: string) {
  const response = await r2.fetch(r2ObjectUrl(key), {
    method: "PUT",
    headers: { "Content-Type": contentType },
    body: bytes,
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new Error(`R2 upload failed (${response.status}): ${detail.slice(0, 300)}`);
  }
}

async function deleteObject(key: string) {
  await r2.fetch(r2ObjectUrl(key), { method: "DELETE" }).catch((error) => {
    console.error("R2 cleanup failed", error);
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    if (![SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
      R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME, R2_PUBLIC_URL]
      .every(Boolean)) {
      console.error("R2 upload function is missing required environment configuration");
      return json({ error: "Image storage is not configured" }, 503);
    }

    const authorization = req.headers.get("Authorization") ?? "";
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return json({ error: "Unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const encoded = String(body.imageBase64 ?? "").replace(/^data:[^;]+;base64,/, "");
    const folder = String(body.folder ?? "posts");
    const contentType = String(body.contentType ?? "image/jpeg").toLowerCase();

    if (!ALLOWED_FOLDERS.has(folder)) return json({ error: "Invalid upload folder" }, 400);
    if (!ALLOWED_TYPES.has(contentType)) return json({ error: "Unsupported image type" }, 415);
    if (!encoded || encoded.length > Math.ceil(MAX_BYTES * 4 / 3) + 8) {
      return json({ error: "Image is empty or too large" }, 413);
    }
    if (!/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) return json({ error: "Invalid image data" }, 400);

    const bytes = decodeBase64(encoded);
    if (bytes.length === 0 || bytes.length > MAX_BYTES) return json({ error: "Image is too large" }, 413);

    // Every user-visible image category must pass server-side moderation before storage.
    {
      const moderationResponse = await fetch(
        `${MEDIA_GATEWAY_URL.replace(/\/$/, "")}/v1/moderate-image`,
        {
          method: "POST",
          headers: { Authorization: authorization, "Content-Type": "application/json" },
          body: JSON.stringify({ imageBase64: encoded, contentType }),
        },
      );
      const moderation = await moderationResponse.json().catch(() => ({}));
      if (!moderationResponse.ok || moderation?.safe !== true) {
        const status = moderationResponse.status === 422 ? 422 : 503;
        return json({
          error: status === 422 ? "Image rejected by server moderation" : "Server moderation unavailable",
          reason: moderation?.reason ?? moderation?.error ?? "Moderation could not approve this image",
        }, status);
      }
    }

    const uid = authData.user.id;
    const key = `${folder}/${uid}/${crypto.randomUUID()}.${extensionFor(contentType)}`;
    await putObject(key, bytes, contentType);
    const publicUrl = `${R2_PUBLIC_URL.replace(/\/$/, "")}/${key}`;

    if (folder !== "posts") return json({ url: publicUrl, objectKey: key });

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });
    const { data: owner, error: ownerError } = await admin
      .from("users")
      .select("isPrivateAccount")
      .eq("uid", uid)
      .maybeSingle();
    if (ownerError || !owner) {
      await deleteObject(key);
      return json({ error: "Post privacy lookup failed" }, 500);
    }

    const { data: post, error: postError } = await admin
      .from("posts")
      .insert({
        userName: uid,
        caption: String(body.caption ?? "No Caption").slice(0, 2000),
        prompt: String(body.prompt ?? "").slice(0, 2000),
        link: String(body.link ?? `app://post/${crypto.randomUUID()}`).slice(0, 2000),
        imageUrl: publicUrl,
        mediaObjectKey: key,
        moderationStatus: "approved",
        moderationCheckedAt: new Date().toISOString(),
        moderationReason: null,
        isPrivatePost: owner.isPrivateAccount === true,
      })
      .select()
      .single();

    if (postError) {
      await deleteObject(key);
      console.error("post insert failed", postError);
      return json({ error: "Post creation failed" }, 500);
    }

    return json({ url: publicUrl, objectKey: key, post });
  } catch (error) {
    console.error("r2-upload failed", error);
    return json({ error: "Image upload failed" }, 500);
  }
});
