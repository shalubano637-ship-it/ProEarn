import { createClient } from "npm:@supabase/supabase-js@2";
import { FirebaseRequestAuthError, verifyFirebaseRequest } from "../_shared/firebase_auth.ts";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const URL = Deno.env.get("SUPABASE_URL") ?? "";
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

async function notifyReporter(reporterId: string, reportId: string, message: string) {
  if (!reporterId) return false;
  const { data: existing, error: lookupError } = await admin.from("notifications")
    .select("id").eq("targetOwnerId", reporterId).eq("type", "report_actioned")
    .eq("requestId", reportId).limit(1);
  if (lookupError) throw lookupError;
  if (existing?.length) return true;
  const { error } = await admin.from("notifications").insert({
    targetOwnerId: reporterId, type: "report_actioned", senderId: "",
    senderName: "ProSN", senderProfile: "", senderProfileUrl: "",
    message, targetPostId: "", requestId: reportId,
  });
  if (error) throw error;
  return true;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (![URL, SERVICE].every(Boolean)) return json({ error: "Moderation service is not configured" }, 503);
  let caller;
  try {
    caller = await verifyFirebaseRequest(req, { requireEmailVerified: true });
  } catch (error) {
    if (error instanceof FirebaseRequestAuthError) return json({ error: error.message }, 401);
    console.error("admin-moderate-report Firebase verifier unavailable", error);
    return json({ error: "Authentication service is unavailable" }, 503);
  }
  if (!caller.email) return json({ error: "Unauthorized" }, 401);
  const { data: adminRow, error: adminError } = await admin.from("admins")
    .select("email").eq("email", caller.email).maybeSingle();
  if (adminError || !adminRow) return json({ error: "Forbidden" }, 403);

  const body = await req.json().catch(() => ({}));
  const reportId = String(body.reportId ?? "");
  const action = String(body.action ?? "remove_message");
  if (!reportId) return json({ error: "reportId is required" }, 400);
  const { data: report, error: reportError } = await admin.from("reports")
    .select("id,targetCommentId,targetMessageId,targetPostId,reportedBy,reportedUserId,source,reason,status")
    .eq("id", reportId).maybeSingle();
  if (reportError || !report) return json({ error: "Report not found" }, 404);

  try {
    if (action === "ban_user") {
      const userId = String(report.reportedUserId ?? "");
      if (!userId) return json({ error: "Report has no reported user" }, 400);
      const { error: banError } = await admin.from("users").update({ isBanned: true }).eq("uid", userId);
      if (banError) throw banError;
      const { error: updateError } = await admin.from("reports").update({
        status: "actioned", actionTaken: "user_banned", reviewedAt: new Date().toISOString(),
        reviewedBy: caller.uid,
      }).eq("id", reportId);
      if (updateError) throw updateError;
      await notifyReporter(String(report.reportedBy ?? ""), reportId,
        "We have reviewed your report and taken action. Appropriate action has been taken on the reported account.");
      return json({ success: true, actionTaken: "user_banned", notificationCreated: true });
    }

    if (action === "delete_post") {
      const postId = String(report.targetPostId ?? "");
      const reporterId = String(report.reportedBy ?? "");
      if (!postId) return json({ error: "Report has no post target" }, 400);

      if (report.status !== "actioned") {
        const { error: deleteError } = await admin.from("posts").delete().eq("id", postId);
        if (deleteError) throw deleteError;

        const { error: updateError } = await admin.from("reports").update({
          status: "actioned", actionTaken: "post_removed", reviewedAt: new Date().toISOString(),
          reviewedBy: caller.uid,
        }).eq("id", reportId);
        if (updateError) throw updateError;

        if (reporterId) {
          await notifyReporter(reporterId, reportId,
            "We have reviewed your report and taken action. The reported post has been removed.");
        }
      }
      return json({ success: true, actionTaken: "post_removed", notificationCreated: true });
    }

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
        reviewedBy: caller.uid,
      }).eq("id", reportId);
      if (updateError) throw updateError;
      await notifyReporter(String(report.reportedBy ?? ""), reportId,
        "We have reviewed your report and taken action. The reported comment has been removed.");
      return json({ success: true, actionTaken: "comment_removed", notificationCreated: true });
    }

    if (action === "remove_room_message") {
      if (report.source !== "room_message") {
        return json({ error: "This report is not a Room message report" }, 400);
      }
      const messageId = String(report.targetMessageId ?? "");
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(messageId)) {
        return json({ error: "Report has no valid Room message target" }, 400);
      }

      const { data: roomMessage, error: roomMessageError } = await admin.from("room_messages")
        .select("id,image_url,voice_path").eq("id", messageId).maybeSingle();
      if (roomMessageError) throw roomMessageError;

      if (roomMessage) {
        // Room images are stored under chat/; room voice notes use voice/<uid>/... keys.
        await removeR2(objectKeyFromUrl(roomMessage.image_url, "chat/"));
        const voiceKey = String(roomMessage.voice_path ?? "");
        if (voiceKey) {
          if (!voiceKey.startsWith("voice/") || voiceKey.startsWith("/") || voiceKey.includes("..")) {
            throw new Error("Room voice attachment has an invalid storage key");
          }
          await removeR2(voiceKey);
        }

        const { error: deleteRoomMessageError } = await admin.from("room_messages")
          .delete().eq("id", messageId);
        if (deleteRoomMessageError) throw deleteRoomMessageError;
      }

      const { error: updateRoomReportError } = await admin.from("reports").update({
        status: "actioned", actionTaken: "room_message_removed", reviewedAt: new Date().toISOString(),
        reviewedBy: caller.uid,
      }).eq("id", reportId);
      if (updateRoomReportError) throw updateRoomReportError;

      await notifyReporter(
        String(report.reportedBy ?? ""),
        reportId,
        roomMessage
          ? "We have reviewed your report and removed the reported Room message."
          : "We have reviewed your report. The reported Room message was already unavailable.",
      );
      return json({
        success: true,
        actionTaken: "room_message_removed",
        messageAlreadyUnavailable: !roomMessage,
      });
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
        reviewedBy: caller.uid,
      }).eq("id", reportId);
      if (updateError) throw updateError;
      return json({ success: true, actionTaken: "chat_message_removed" });
    }

    if (action === "dismiss") {
      const { error } = await admin.from("reports").update({
        status: "dismissed", actionTaken: "dismissed", reviewedAt: new Date().toISOString(),
        reviewedBy: caller.uid,
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