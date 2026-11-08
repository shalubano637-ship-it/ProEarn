import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const mediaGatewayUrl = Deno.env.get("MEDIA_GATEWAY_URL") ?? "https://proearn-media-gateway.0nasir07860.workers.dev";
const mediaInternalToken = Deno.env.get("MEDIA_INTERNAL_TOKEN") ?? "";
const r2PublicUrl = (Deno.env.get("R2_PUBLIC_URL") ?? "").replace(/\/$/, "");

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "content-type": "application/json", "cache-control": "no-store" },
  });
}

function assertNoError(operation: string, error: { message: string } | null) {
  if (error) throw new Error(`${operation}: ${error.message}`);
}

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function getOwnedR2Key(value: unknown, ownerUid: string): string | null {
  if (typeof value !== "string" || !value || !r2PublicUrl || !value.startsWith(`${r2PublicUrl}/`)) {
    return null;
  }
  try {
    const key = decodeURIComponent(new URL(value).pathname.replace(/^\/+/, ""));
    if (!key.startsWith(`chat/${ownerUid}/`) || key.length > 1024 || key.includes("..")) return null;
    return key;
  } catch {
    return null;
  }
}

async function deleteChatObject(userId: string, objectKey: string) {
  if (!mediaInternalToken) throw new Error("Media deletion token is not configured");
  const response = await fetch(`${mediaGatewayUrl.replace(/\/$/, "")}/internal/delete-media-object`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-internal-token": mediaInternalToken,
    },
    body: JSON.stringify({ userId, objectKey }),
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new Error(`Chat media cleanup failed (HTTP ${response.status}): ${detail.slice(0, 200)}`);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!supabaseUrl || !anonKey || !serviceRoleKey) return json({ error: "Moderation service is not configured" }, 503);

  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  const user = authData.user;
  if (authError || !user?.email) return json({ error: "Unauthorized" }, 401);

  const { data: adminRecord, error: adminError } = await admin
    .from("admins")
    .select("email")
    .eq("email", user.email.toLowerCase())
    .maybeSingle();
  if (adminError) {
    console.error("Admin authorization lookup failed", adminError);
    return json({ error: "Could not verify moderator access" }, 500);
  }
  if (!adminRecord) return json({ error: "Forbidden" }, 403);

  const body = await req.json().catch(() => ({}));
  const reportId = String(body.reportId ?? "");
  if (!reportId) return json({ error: "reportId required" }, 400);

  try {
    const { data: report, error: reportError } = await admin
      .from("reports")
      .select("id,source,targetMessageId")
      .eq("id", reportId)
      .maybeSingle();
    assertNoError("Load moderation report", reportError);
    if (!report || report.source !== "chat_message" || !report.targetMessageId) {
      return json({ error: "This report is not linked to a chat message" }, 404);
    }

    const { data: message, error: messageError } = await admin
      .from("messages")
      .select("id,senderId,imageUrl,voicePath")
      .eq("id", report.targetMessageId)
      .maybeSingle();
    assertNoError("Load reported chat message", messageError);

    let legacyMediaMayRemain = false;
    if (message) {
      const keys = new Set<string>();
      for (const value of [message.imageUrl, message.voicePath]) {
        if (value == null || value === "") continue;
        const key = getOwnedR2Key(value, message.senderId);
        if (key) keys.add(key);
        else legacyMediaMayRemain = true;
      }
      for (const key of keys) {
        await deleteChatObject(message.senderId, key);
      }

      const { error: hideError } = await admin
        .from("messages")
        .update({
          deletedForEveryone: true,
          text: null,
          imageUrl: null,
          voicePath: null,
          voiceDurationMs: null,
        })
        .eq("id", message.id);
      assertNoError("Remove reported chat message", hideError);
    }

    const { error: reportUpdateError } = await admin
      .from("reports")
      .update({
        status: "actioned",
        actionTaken: message ? "chat_message_removed" : "chat_message_already_removed",
        reviewedAt: new Date().toISOString(),
        reviewedBy: user.id,
      })
      .eq("id", reportId);
    assertNoError("Update moderation report", reportUpdateError);

    return json({ success: true, legacyMediaMayRemain });
  } catch (error) {
    console.error("admin-moderate-report failed", error);
    return json({ error: "Could not remove the reported chat message. Retry or inspect the report." }, 500);
  }
});
