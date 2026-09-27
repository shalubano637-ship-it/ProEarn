import { AwsClient } from "npm:aws4fetch@1.0.20";

interface Env {
  R2_BUCKET: R2Bucket;
  R2_ACCOUNT_ID: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  R2_PUBLIC_BASE_URL: string;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  INTERNAL_DELETE_TOKEN: string;
  AI: Ai;
}

const MAX_IMAGE_BYTES = 9 * 1024 * 1024;
const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

async function getUser(request: Request, env: Env) {
  const auth = request.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return null;
  const response = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: auth, apikey: env.SUPABASE_ANON_KEY },
  });
  if (!response.ok) return null;
  const user = await response.json<{ id: string; email?: string }>();

  const profileResponse = await fetch(
    `${env.SUPABASE_URL}/rest/v1/users?uid=eq.${encodeURIComponent(user.id)}&select=termsAcceptedAt,termsVersion,isBanned&limit=1`,
    { headers: { Authorization: auth, apikey: env.SUPABASE_ANON_KEY } },
  );
  if (!profileResponse.ok) return null;
  const profiles = await profileResponse.json<Array<{ termsAcceptedAt?: string | null; termsVersion?: string | null; isBanned?: boolean }>>();
  const profile = profiles[0];
  if (!profile || !profile.termsAcceptedAt || profile.termsVersion !== '2026-09' || profile.isBanned === true) return null;
  return user;
}

function r2Key(userId: string, folder: string, extension: string) {
  const safeFolder = folder === "profile" ? "profile" : folder === "chat" ? "chat" : "posts";
  return `${safeFolder}/${userId}/${crypto.randomUUID()}.${extension}`;
}

async function signedPutUrl(env: Env, key: string, contentType: string) {
  const client = new AwsClient({
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
  });
  const encodedKey = key.split("/").map(encodeURIComponent).join("/");
  const url = new URL(`https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/proearn-media/${encodedKey}`);
  url.searchParams.set("X-Amz-Expires", "900");
  const signed = await client.sign(
    new Request(url, { method: "PUT", headers: { "Content-Type": contentType } }),
    { aws: { signQuery: true } },
  );
  return signed.url;
}

function bytesToBase64(bytes: Uint8Array) {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, Math.min(i + chunk, bytes.length)));
  }
  return btoa(binary);
}

async function moderateBytes(env: Env, bytes: Uint8Array, contentType: string, userId: string) {
  if (!ALLOWED_TYPES.has(contentType)) return { safe: false, reason: "Unsupported image type" };
  if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) return { safe: false, reason: "Image too large" };

  const dataUrl = `data:${contentType};base64,${bytesToBase64(bytes)}`;

  try {
    const response = await env.AI.run("@cf/meta/llama-4-scout-17b-16e-instruct", {
      messages: [
        {
          role: "system",
          content: 'You are Pro Earn\'s server-side safety classifier. Return ONLY JSON: {"safe":true|false,"reason":"short reason"}. Reject pornography, nudity, explicit sexual activity, sexualized minors, child exploitation, grooming material, graphic gore, or imagery that clearly promotes violent wrongdoing. Normal people, art, fashion, sports, medical/educational material, and non-graphic everyday scenes are safe unless they clearly contain prohibited content. Be conservative when uncertain.',
        },
        {
          role: "user",
          content: [
            { type: "text", text: `Classify this uploaded image for userId ${userId}.` },
            { type: "image_url", image_url: { url: dataUrl } },
          ],
        },
      ],
      max_tokens: 80,
      temperature: 0,
    });

    const raw = typeof response === "string" ? response : response?.response ?? JSON.stringify(response);
    const cleaned = String(raw).replace(/^\`\`\`json\s*/i, "").replace(/\`\`\`$/i, "").trim();
    const parsed = JSON.parse(cleaned) as { safe?: boolean; reason?: string };
    return {
      safe: parsed.safe === true,
      reason: parsed.reason ?? (parsed.safe ? undefined : "Server moderation rejected the image"),
    };
  } catch (error) {
    console.error("server moderation failed", error);
    return { safe: false, reason: "Server moderation unavailable" };
  }
}

async function moderate(env: Env, objectKey: string, userId: string) {
  const object = await env.R2_BUCKET.get(objectKey);
  if (!object) return { safe: false, reason: "Uploaded object not found" };
  const contentType = object.httpMetadata?.contentType ?? "image/jpeg";
  const bytes = new Uint8Array(await object.arrayBuffer());
  return moderateBytes(env, bytes, contentType, userId);
}

async function createPost(env: Env, userId: string, body: Record<string, unknown>, imageUrl: string, objectKey: string) {
  const response = await fetch(`${env.SUPABASE_URL}/rest/v1/posts`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: JSON.stringify({
      userName: userId,
      caption: String(body.caption ?? "No Caption"),
      prompt: String(body.prompt ?? ""),
      link: String(body.link ?? `app://post/${Date.now()}`),
      imageUrl,
      moderationStatus: "approved",
      moderationCheckedAt: new Date().toISOString(),
      moderationReason: null,
      mediaObjectKey: objectKey,
    }),
  });
  if (!response.ok) throw new Error(`post_insert_failed:${response.status}`);
  return await response.json();
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { status: 204 });
    const url = new URL(request.url);
    const user = await getUser(request, env);
    if (!user) return json({ error: "Unauthorized" }, 401);

    try {
      if (url.pathname === "/v1/moderate-image" && request.method === "POST") {
        const body = await request.json<{ imageBase64?: string; contentType?: string }>();
        const imageBase64 = String(body.imageBase64 ?? "").replace(/^data:[^;]+;base64,/, "");
        const contentType = String(body.contentType ?? "image/jpeg");
        if (!imageBase64) return json({ error: "imageBase64 required" }, 400);
        if (imageBase64.length > 12000000) return json({ error: "Image too large" }, 400);

        let binary: string;
        try {
          binary = atob(imageBase64);
        } catch {
          return json({ error: "Invalid base64 image" }, 400);
        }
        const bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
        const moderation = await moderateBytes(env, bytes, contentType, user.id);
        if (!moderation.safe) {
          return json({ safe: false, reason: moderation.reason ?? "Content rejected" }, 422);
        }
        return json({ safe: true });
      }

      if (url.pathname === "/internal/delete-user-media" && request.method === "POST") {
        const token = request.headers.get("x-internal-token") ?? "";
        if (!token || token !== env.INTERNAL_DELETE_TOKEN) return json({ error: "Forbidden" }, 403);
        const body = await request.json<{ userId?: string }>();
        const userId = String(body.userId ?? "");
        if (!/^[0-9a-f-]{36}$/i.test(userId)) return json({ error: "Invalid userId" }, 400);

        let deleted = 0;
        for (const prefix of ["posts/" + userId + "/", "profile/" + userId + "/", "chat/" + userId + "/"]) {
          let cursor: string | undefined;
          do {
            const listed = await env.R2_BUCKET.list({ prefix, cursor, limit: 1000 });
            const keys = listed.objects.map((object) => object.key);
            for (let i = 0; i < keys.length; i += 1000) {
              const chunk = keys.slice(i, i + 1000);
              if (chunk.length) { await env.R2_BUCKET.delete(chunk); deleted += chunk.length; }
            }
            cursor = listed.truncated ? listed.cursor : undefined;
          } while (cursor);
        }
        return json({ success: true, deleted });
      }
      if (url.pathname === "/v1/upload-intent" && request.method === "POST") {
        const body = await request.json<{ contentType?: string; folder?: string }>();
        const contentType = String(body.contentType ?? "");
        if (!ALLOWED_TYPES.has(contentType)) return json({ error: "Unsupported image type" }, 400);
        const extension = contentType === "image/png" ? "png" : contentType === "image/webp" ? "webp" : "jpg";
        const key = r2Key(user.id, String(body.folder ?? "posts"), extension);
        const uploadUrl = await signedPutUrl(env, key, contentType);
        return json({ uploadUrl, objectKey: key, maxBytes: MAX_IMAGE_BYTES });
      }

      if (url.pathname === "/v1/finalize-media" && request.method === "POST") {
        const body = await request.json<Record<string, unknown>>();
        const objectKey = String(body.objectKey ?? "");
        const contentType = String(body.contentType ?? "");
        const size = Number(body.size ?? 0);
        if (!objectKey.startsWith(`${String(body.folder ?? "posts")}/${user.id}/`)) return json({ error: "Invalid object" }, 403);
        if (!ALLOWED_TYPES.has(contentType) || size <= 0 || size > MAX_IMAGE_BYTES) return json({ error: "Invalid upload" }, 400);

        const moderation = await moderate(env, objectKey, user.id);
        if (!moderation.safe) {
          await env.R2_BUCKET.delete(objectKey);
          return json({ error: "Content rejected", reason: moderation.reason }, 422);
        }
        const mediaUrl = `${env.R2_PUBLIC_BASE_URL.replace(/\/$/, "")}/${objectKey}`;
        return json({ url: mediaUrl });
      }

      if (url.pathname === "/v1/finalize-post" && request.method === "POST") {
        const body = await request.json<Record<string, unknown>>();
        const objectKey = String(body.objectKey ?? "");
        const contentType = String(body.contentType ?? "");
        const size = Number(body.size ?? 0);
        if (!objectKey.startsWith(`posts/${user.id}/`)) return json({ error: "Invalid object" }, 403);
        if (!ALLOWED_TYPES.has(contentType) || size <= 0 || size > MAX_IMAGE_BYTES) return json({ error: "Invalid upload" }, 400);

        const moderation = await moderate(env, objectKey, user.id);
        if (!moderation.safe) {
          await env.R2_BUCKET.delete(objectKey);
          return json({ error: "Content rejected", reason: moderation.reason }, 422);
        }

        const imageUrl = `${env.R2_PUBLIC_BASE_URL.replace(/\/$/, "")}/${objectKey}`;
        try {
          const post = await createPost(env, user.id, body, imageUrl, objectKey);
          return json({ post, url: imageUrl });
        } catch (error) {
          await env.R2_BUCKET.delete(objectKey);
          throw error;
        }
      }

      return json({ error: "Not found" }, 404);
    } catch (error) {
      console.error(error);
      return json({ error: "Internal error" }, 500);
    }
  },
} satisfies ExportedHandler<Env>;
