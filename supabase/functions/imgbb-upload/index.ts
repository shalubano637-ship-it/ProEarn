
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const IMGBB_API_KEY = Deno.env.get("IMGBB_API_KEY")!;
const MODERATION_SHARED_SECRET = Deno.env.get("MODERATION_SHARED_SECRET")!;

const MAX_BASE64_LENGTH = 12_000_000; // ~9MB decoded, generous ceiling for a compressed photo

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function decodeBase64Url(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - normalized.length % 4) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function verifyModerationApproval(
  token: string,
  imageBase64: string,
  userId: string,
): Promise<boolean> {
  if (!MODERATION_SHARED_SECRET || !token) return false;

  const parts = token.split(".");
  if (parts.length !== 3) return false;

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(
      new TextDecoder().decode(decodeBase64Url(encodedPayload)),
    );
  } catch {
    return false;
  }

  if (
    payload.approved !== true ||
    payload.sub !== userId ||
    typeof payload.sha256 !== "string" ||
    typeof payload.exp !== "number" ||
    payload.exp <= Math.floor(Date.now() / 1000)
  ) {
    return false;
  }

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(MODERATION_SHARED_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );

  const validSignature = await crypto.subtle.verify(
    "HMAC",
    key,
    decodeBase64Url(encodedSignature),
    new TextEncoder().encode(encodedHeader + "." + encodedPayload),
  );
  if (!validSignature) return false;

  const imageBytes = decodeBase64Url(imageBase64);
  const digest = await crypto.subtle.digest("SHA-256", imageBytes);
  return bytesToHex(new Uint8Array(digest)) === payload.sha256;
}

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

    const moderationApprovalToken = String(body.moderationApprovalToken ?? "");
    const approved = await verifyModerationApproval(
      moderationApprovalToken,
      imageBase64,
      userData.user.id,
    );
    if (!approved) {
      return json({ error: "Server moderation approval required" }, 403);
    }

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

    const imageUrl = data.data.url as string;
    const { data: owner, error: ownerError } = await authed
      .from("users")
      .select("isPrivateAccount")
      .eq("uid", userData.user.id)
      .maybeSingle();
    if (ownerError) {
      console.error("Owner privacy lookup failed:", ownerError);
      return json({ error: "Post privacy lookup failed" }, 500);
    }
    const { data: post, error: postError } = await authed
      .from("posts")
      .insert({
        userName: userData.user.id,
        caption: String(body.caption ?? "No Caption"),
        prompt: String(body.prompt ?? ""),
        link: String(body.link ?? `app://post/${Date.now()}`),
        imageUrl,
        moderationStatus: "approved",
        moderationCheckedAt: new Date().toISOString(),
        moderationReason: null,
        mediaObjectKey: null,
        isPrivatePost: owner?.isPrivateAccount === true,
      })
      .select()
      .single();

    if (postError) {
      console.error("Post insert failed:", postError);
      return json({ error: "Post creation failed" }, 500);
    }

    return json({ url: imageUrl, post });
  } catch (e) {
    console.error("imgbb-upload error:", e);
    return json({ error: "Internal error" }, 500);
  }
});
