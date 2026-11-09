import { createClient } from "npm:@supabase/supabase-js@2";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const URL = Deno.env.get("SUPABASE_URL") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const R2_ACCOUNT_ID = Deno.env.get("R2_ACCOUNT_ID") ?? "";
const R2_ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID") ?? "";
const R2_SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY") ?? "";
const R2_BUCKET_NAME = Deno.env.get("R2_BUCKET_NAME") ?? "";
const R2_PUBLIC_URL = (Deno.env.get("R2_PUBLIC_URL") ?? "").replace(/\/$/, "");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const admin = createClient(URL, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });
const r2 = new AwsClient({
  accessKeyId: R2_ACCESS_KEY_ID, secretAccessKey: R2_SECRET_ACCESS_KEY,
  service: "s3", region: "auto",
});
function objectKeyFromUrl(value: unknown, allowedPrefix: string): string | null {
  if (typeof value !== "string" || !R2_PUBLIC_URL || !value.startsWith(R2_PUBLIC_URL + "/")) return null;
  const key = value.slice(R2_PUBLIC_URL.length + 1).split("?")[0];
  if (!key.startsWith(allowedPrefix) || key.includes("..") || key.startsWith("/")) return null;
  return key;
}
async function removeR2(key: string | null) {
  if (!key) return;
  if (![R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME].every(Boolean)) {
    throw new Error("R2 deletion is not configured");
  }
  const encoded = key.split("/").map(encodeURIComponent).join("/");
  const url = `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${R2_BUCKET_NAME}/${encoded}`;
  const response = await r2.fetch(url, { method: "DELETE" });
  if (!response.ok && response.status !== 404) throw new Error(`R2 object deletion failed: ${response.status}`);
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (![URL, ANON, SERVICE].every(Boolean)) return json({ error: "Moderation service is not configured" }, 503);
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);
  const caller = createClient(URL, ANON, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: auth, error: authError } = await caller.auth.getUser();
  if (authError || !auth.user?.email) return json({ error: "Unauthorized" }, 401);
  const { data: adminRow, error: adminError } = await admin.from("admins")
    .select("email").eq("email", auth.user.email.toLowerCase()).maybeSingle();
  if (adminError || !adminRow) return json({ error: "Forbidden" }, 403);

  const body = await req.json().catch(() => ({}));
  const reportId = String(body.reportId ?? "");
  const action = String(body.action ?? "remove_message");
  if (!reportId) return json({ error: "reportId is required" }, 400);
  const { data: report, error: reportError } = await admin.from("reports")
    .select("id,targetCommentId,targetMessageId,targetPostId,source,reason,status")
    .eq("id", reportId).maybeSingle();
  if (reportError || !report) return json({ error: "Report not found" }, 404);

  try {
    if (action === "delete_comment") {
      const commentId = String(report.targetCommentId ?? "");
      if (!commentId) return json({ error: "Report has no comment target" }, 400);
      const { data: comment, error } = await admin.from("comments")
        .select("id,imageUrl").eq("id", commentId).maybeSingle();
      if (error) throw error;
      if (comment) {
        await removeR2(objectKeyFromUrl(comment.imageUrl, "comments/"));
        const { error: repliesError } = await admin.from("comments")
          .update({ parentCommentId: null, replyToUserId: null, replyToUsername: null })
          .eq("parentCommentId", commentId);
        if (repliesError) throw repliesError;
        const { error: deleteError } = await admin.from("comments").delete().eq("id", commentId);
        if (deleteError) throw deleteError;
      }
      const { error: updateError } = await admin.from("reports").update({
        status: "actioned", actionTaken: "comment_removed", reviewedAt: new Date().toISOString(),
        reviewedBy: auth.user.id,
      }).eq("id", reportId);
      if (updateError) throw updateError;
      return json({ success: true, actionTaken: "comment_removed" });
    }

    if (action === "remove_message" || action === "delete_message") {
      const messageId = String(report.targetMessageId ?? "");
      if (!messageId) return json({ error: "Report has no message target" }, 400);
      const { data: message, error } = await admin.from("messages")
        .select("id,imageUrl,voicePath").eq("id", messageId).maybeSingle();
      if (error) throw error;
      if (message) {
        await removeR2(objectKeyFromUrl(message.imageUrl, "chat/"));
        await removeR2(objectKeyFromUrl(message.voicePath, "chat/"));
        const { error: updateMessageError } = await admin.from("messages").update({
          text: "[Message removed by moderation]", imageUrl: null, voicePath: null,
          deletedForEveryone: true,
        }).eq("id", messageId);
        if (updateMessageError) throw updateMessageError;
      }
      const { error: updateError } = await admin.from("reports").update({
        status: "actioned", actionTaken: "chat_message_removed", reviewedAt: new Date().toISOString(),
        reviewedBy: auth.user.id,
      }).eq("id", reportId);
      if (updateError) throw updateError;
      return json({ success: true, actionTaken: "chat_message_removed" });
    }

    if (action === "dismiss") {
      const { error } = await admin.from("reports").update({
        status: "dismissed", actionTaken: "dismissed", reviewedAt: new Date().toISOString(),
        reviewedBy: auth.user.id,
      }).eq("id", reportId);
      if (error) throw error;
      return json({ success: true, actionTaken: "dismissed" });
    }
    return json({ error: "Unsupported moderation action" }, 400);
  } catch (error) {
    console.error("admin-moderate-report failed", { reportId, action, error });
    return json({ error: "Moderation action failed. No success was recorded." }, 500);
  }
});