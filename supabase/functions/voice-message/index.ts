import { createClient } from "npm:@supabase/supabase-js@2";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const MAX_BYTES = 8 * 1024 * 1024;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const R2_ACCOUNT_ID = Deno.env.get("R2_ACCOUNT_ID") ?? "";
const R2_ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID") ?? "";
const R2_SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY") ?? "";
const R2_BUCKET_NAME = Deno.env.get("R2_BUCKET_NAME") ?? "";
const R2_ENDPOINT = R2_ACCOUNT_ID ? `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com` : "";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(body: unknown, status = 200) {
  return Response.json(body, { status, headers: { ...CORS, "Cache-Control": "no-store" } });
}
function decodeBase64(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(normalized + "=".repeat((4 - normalized.length % 4) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
function objectUrl(key: string) {
  return `${R2_ENDPOINT}/${R2_BUCKET_NAME}/${key.split("/").map(encodeURIComponent).join("/")}`;
}
const r2 = new AwsClient({
  accessKeyId: R2_ACCESS_KEY_ID,
  secretAccessKey: R2_SECRET_ACCESS_KEY,
  service: "s3",
  region: "auto",
});
function assertR2Configured() {
  if (![R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME].every(Boolean)) {
    throw new Error("R2 voice storage is not configured");
  }
}
async function putVoiceObject(key: string, bytes: Uint8Array) {
  const result = await r2.fetch(objectUrl(key), {
    method: "PUT",
    headers: { "Content-Type": "audio/mp4" },
    body: bytes as unknown as BodyInit,
  });
  if (!result.ok) throw new Error(`R2 voice upload failed (${result.status}): ${(await result.text().catch(() => "")).slice(0, 250)}`);
}
async function deleteVoiceObject(key: string) {
  const result = await r2.fetch(objectUrl(key), { method: "DELETE" });
  if (!result.ok && result.status !== 404) throw new Error(`R2 voice cleanup failed (${result.status})`);
}
async function signedVoiceUrl(key: string) {
  const url = new URL(objectUrl(key));
  url.searchParams.set("X-Amz-Expires", "300");
  const signed = await r2.sign(new Request(url), { aws: { signQuery: true } });
  return signed.url.toString();
}

Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") return response({ error: "Method not allowed" }, 405);
    try {
      assertR2Configured();
      if (![SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY].every(Boolean)) {
        console.error("voice-message is missing Supabase environment configuration");
        return response({ error: "Voice messaging is not configured" }, 503);
      }
      const authorization = req.headers.get("Authorization") ?? "";
      if (!authorization.startsWith("Bearer ")) return response({ error: "Unauthorized" }, 401);
      const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data: authData, error: authError } = await userClient.auth.getUser();
      if (authError || !authData.user) {
        console.error("voice-message authentication failed", authError?.message ?? "No user");
        return response({ error: "Unauthorized" }, 401);
      }
      const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const body = await req.json().catch(() => ({}));
      const mode = String(body.mode ?? "");

      if (mode === "upload") {
        const audioBase64 = String(body.audioBase64 ?? "");
        const durationMs = Number(body.durationMs ?? 0);
        const listenLimit = Number(body.listenLimit ?? 1);
        const conversationId = body.conversationId ? String(body.conversationId) : null;
        const roomId = body.roomId ? String(body.roomId) : null;
        const replyToMessageId = body.replyToMessageId ? String(body.replyToMessageId) : null;
        if (!audioBase64) return response({ error: "Audio is missing" }, 400);
        if (audioBase64.length > MAX_BYTES * 1.4) return response({ error: "Audio is too large" }, 400);
        if (durationMs < 300 || durationMs > 120000) return response({ error: "Voice must be 0.3 to 120 seconds" }, 400);
        if (![1, 2].includes(listenLimit)) return response({ error: "Listen limit must be 1 or 2" }, 400);
        if ((!conversationId && !roomId) || (conversationId && roomId)) return response({ error: "Invalid destination" }, 400);
        const bytes = decodeBase64(audioBase64);
        if (!bytes.length || bytes.length > MAX_BYTES) return response({ error: "Audio is too large" }, 400);
        const uid = authData.user.id;
        if (!uid) return response({ error: "Unauthorized" }, 401);
        const key = `voice/${uid}/${crypto.randomUUID()}.m4a`;
        await putVoiceObject(key, bytes);
        try {
          let messageId: string;
          if (conversationId) {
            const { data, error } = await userClient.rpc("send_voice_message", {
              p_conversation_id: conversationId, p_voice_path: key,
              p_voice_duration_ms: Math.round(durationMs), p_voice_listen_limit: listenLimit,
              p_reply_to_message_id: replyToMessageId,
            });
            if (error) throw error;
            messageId = String(data);
          } else {
            const { data, error } = await userClient.rpc("send_room_voice_message", {
              p_room_id: roomId, p_voice_path: key,
              p_voice_duration_ms: Math.round(durationMs), p_voice_listen_limit: listenLimit,
              p_reply_to_message_id: replyToMessageId || null,
            });
            if (error) throw error;
            messageId = String(data);
          }
          return response({ messageId, voicePath: key, durationMs: Math.round(durationMs), listenLimit });
        } catch (error) {
          await deleteVoiceObject(key).catch((e) => console.error("R2 rollback cleanup failed", e));
          throw error;
        }
      }

      if (mode === "play") {
        const messageId = String(body.messageId ?? "");
        const room = body.room === true;
        if (!messageId) return response({ error: "messageId is required" }, 400);
        const rpc = room
          ? await userClient.rpc("consume_room_voice_message", { p_message_id: messageId })
          : await userClient.rpc("consume_voice_message", { p_message_id: messageId });
        if (rpc.error || !rpc.data?.length) return response({ error: rpc.error?.message ?? "Voice message is no longer available" }, 410);
        const row = rpc.data[0];
        const key = String(row.voice_path ?? "");
        if (!key.startsWith("voice/") || key.includes("..")) return response({ error: "Invalid voice object reference" }, 500);
        return response({
          url: await signedVoiceUrl(key),
          durationMs: Number(row.voice_duration_ms ?? 0),
          listenCount: Number(row.voice_listen_count ?? 0),
          listenLimit: Number(row.voice_listen_limit ?? 1),
          finalPlay: row.is_final_play === true,
        });
      }

      if (mode === "cleanup") {
        const messageId = String(body.messageId ?? "");
        const room = body.room === true;
        if (!messageId) return response({ error: "messageId is required" }, 400);
        const allowed = await userClient.rpc("cleanup_voice_message", { p_message_id: messageId, p_room: room });
        if (allowed.error || allowed.data !== true) return response({ cleaned: false });
        const table = room ? "room_messages" : "messages";
        const pathColumn = room ? "voice_path" : "voicePath";
        const { data: row, error } = await adminClient.from(table).select(pathColumn).eq("id", messageId).maybeSingle();
        if (error || !row) return response({ cleaned: false });
        const key = String(row[pathColumn] ?? "");
        if (key) {
          if (!key.startsWith("voice/") || key.includes("..")) return response({ cleaned: false }, 500);
          await deleteVoiceObject(key);
          await adminClient.from(table).update({ [pathColumn]: null }).eq("id", messageId);
        }
        return response({ cleaned: true });
      }
      return response({ error: "Unknown mode" }, 400);
    } catch (error) {
      console.error("voice-message error", error);
      return response({ error: String((error as Error)?.message ?? error) }, 500);
    }
});
