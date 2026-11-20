import { createClient } from "npm:@supabase/supabase-js@2";
import { cert, getApps, initializeApp } from "npm:firebase-admin@13.2.0/app";
import { getAuth } from "npm:firebase-admin@13.2.0/auth";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const mediaGatewayUrl = Deno.env.get("MEDIA_GATEWAY_URL") ?? "https://proearn-media-gateway.0nasir07860.workers.dev";
const mediaInternalToken = Deno.env.get("MEDIA_INTERNAL_TOKEN") ?? "";

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

function firebaseAdminAuth() {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("Firebase Admin service account is not configured");
  const serviceAccount = JSON.parse(raw);
  if (serviceAccount.project_id !== "proearn-6acdd") throw new Error("Firebase project mismatch");
  const app = getApps()[0] ?? initializeApp({ credential: cert(serviceAccount), projectId: serviceAccount.project_id });
  return getAuth(app);
}

async function deleteWhere(table: string, column: string, value: string) {
  const { error } = await admin.from(table).delete().eq(column, value);
  assertNoError(`Delete ${table} by ${column}`, error);
}

async function removePostLikes(uid: string) {
  while (true) {
    const { data, error } = await admin.from("posts").select("id,likedBy")
      .contains("likedBy", [uid]).order("id", { ascending: true }).limit(500);
    assertNoError("Read post likes", error);
    const rows = data ?? [];
    if (rows.length === 0) break;
    for (let i = 0; i < rows.length; i += 20) {
      await Promise.all(rows.slice(i, i + 20).map(async (row: Record<string, unknown>) => {
        const likedBy = Array.isArray(row.likedBy) ? row.likedBy : [];
        const { error: updateError } = await admin.from("posts")
          .update({ likedBy: likedBy.filter((entry) => entry !== uid) }).eq("id", row.id);
        assertNoError("Remove deleted user from post likes", updateError);
      }));
    }
  }
}

async function removeCommentReferences(uid: string) {
  const { data: ownComments, error: readError } = await admin.from("comments")
    .select("id").eq("userId", uid);
  assertNoError("Read comments authored by deleted user", readError);
  const commentIds = (ownComments ?? []).map((row: { id: string }) => row.id).filter(Boolean);
  if (commentIds.length > 0) {
    const { error: parentError } = await admin.from("comments")
      .update({ parentCommentId: null, replyToUserId: null, replyToUsername: null })
      .in("parentCommentId", commentIds);
    assertNoError("Clear replies to deleted comments", parentError);
  }
  const { error: replyUserError } = await admin.from("comments")
    .update({ replyToUserId: null, replyToUsername: null }).eq("replyToUserId", uid);
  assertNoError("Clear reply references to deleted user", replyUserError);
}

async function removeUserReferences(uid: string) {
  let offset = 0;
  const pageSize = 500;
  while (true) {
    const { data, error } = await admin.from("users")
      .select("uid,followers,following,blockedUsers,hiddenPosts,mutedUsers,referredBy")
      .neq("uid", uid).order("uid", { ascending: true }).range(offset, offset + pageSize - 1);
    assertNoError("Read user references", error);
    const rows = data ?? [];
    for (let i = 0; i < rows.length; i += 20) {
      await Promise.all(rows.slice(i, i + 20).map(async (row: Record<string, unknown>) => {
        const patch: Record<string, unknown> = {};
        for (const field of ["followers", "following", "blockedUsers", "hiddenPosts", "mutedUsers"]) {
          const value = row[field];
          if (Array.isArray(value) && value.includes(uid)) patch[field] = value.filter((entry) => entry !== uid);
        }
        if (row.referredBy === uid) patch.referredBy = null;
        if (Object.keys(patch).length === 0) return;
        const { error: updateError } = await admin.from("users").update(patch).eq("uid", row.uid);
        assertNoError("Remove references from users", updateError);
      }));
    }
    if (rows.length < pageSize) break;
    offset += pageSize;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!supabaseUrl || !serviceRoleKey || !Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")) return json({ error: "Account deletion service is not configured" }, 503);
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);
  let firebaseUser;
  try {
    const firebaseAuth = firebaseAdminAuth();
    const decoded = await firebaseAuth.verifyIdToken(authorization.slice(7), true);
    if (decoded.role !== "authenticated" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(decoded.uid)) {
      return json({ error: "Unauthorized" }, 401);
    }
    firebaseUser = await firebaseAuth.getUser(decoded.uid);
  } catch (_) {
    return json({ error: "Unauthorized" }, 401);
  }
  const uid = firebaseUser.uid;
  try {
    await removeCommentReferences(uid);
    const { error: commentError } = await admin.from("comments").delete().eq("userId", uid);
    assertNoError("Delete user's comments", commentError);
    const { error: postError } = await admin.from("posts").delete().eq("userName", uid);
    assertNoError("Delete user's posts", postError);
    await removePostLikes(uid);
    const { data: conversations, error: conversationReadError } = await admin.from("conversations")
      .select("id").or(`participantA.eq.${uid},participantB.eq.${uid}`);
    assertNoError("Find user's conversations", conversationReadError);
    const conversationIds = (conversations ?? []).map((row: { id: string }) => row.id).filter(Boolean);
    if (conversationIds.length > 0) {
      const { error: requestError } = await admin.from("message_requests").delete().in("conversationId", conversationIds);
      assertNoError("Delete conversation requests", requestError);
      const { error: messageError } = await admin.from("messages").delete().in("conversationId", conversationIds);
      assertNoError("Delete conversation messages", messageError);
      const { error: conversationError } = await admin.from("conversations").delete().in("id", conversationIds);
      assertNoError("Delete conversations", conversationError);
    }
    await deleteWhere("messages", "senderId", uid);
    await deleteWhere("message_requests", "senderId", uid);
    await deleteWhere("message_requests", "recipientId", uid);
    await deleteWhere("cooldowns", "userId", uid);
    await deleteWhere("room_messages", "sender_id", uid);
    const { error: presenceError } = await admin.from("user_presence")
      .update({ chattingWithUid: null }).eq("chattingWithUid", uid);
    assertNoError("Clear other users' active chat presence", presenceError);
    await deleteWhere("notifications", "senderId", uid);
    await deleteWhere("notification_delivery_dedup", "senderId", uid);
    await deleteWhere("notification_delivery_dedup", "targetOwnerId", uid);
    await deleteWhere("follow_action_log", "actorUid", uid);
    await deleteWhere("ad_gift_claims", "uid", uid);
    await deleteWhere("daily_like_counts", "uid", uid);
    const { error: reporterError } = await admin.from("reports").update({ reportedBy: "deleted-user" }).eq("reportedBy", uid);
    assertNoError("Anonymize reports submitted by deleted user", reporterError);
    const { error: targetError } = await admin.from("reports").update({ reportedUserId: null }).eq("reportedUserId", uid);
    assertNoError("Remove deleted user from report targets", targetError);
    await removeUserReferences(uid);
    if (!mediaGatewayUrl || !mediaInternalToken) throw new Error("Media deletion service is not configured");
    const mediaResponse = await fetch(`${mediaGatewayUrl.replace(/\/$/, "")}/internal/delete-user-media`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-internal-token": mediaInternalToken },
      body: JSON.stringify({ userId: uid }),
    });
    if (!mediaResponse.ok) {
      const detail = await mediaResponse.text().catch(() => "");
      throw new Error(`Media deletion failed (HTTP ${mediaResponse.status}): ${detail.slice(0, 200)}`);
    }
    const email = firebaseUser.email?.toLowerCase();
    if (email) {
      const { error: adminCleanupError } = await admin.from("admins").delete().eq("email", email);
      assertNoError("Remove admin mapping", adminCleanupError);
    }
    // Remove the public profile explicitly: this schema does not cascade public.users from auth.users.\n    await deleteWhere("users", "uid", uid);\n    // Firebase identity is deleted only after all application data and media cleanup succeeds.
    await firebaseAdminAuth().deleteUser(uid);
    return json({ success: true, r2MediaDeleted: true });
  } catch (error) {
    console.error("delete-account failed", { userId: uid, error });
    return json({ error: "Account deletion could not be completed. Your sign-in remains available so you can retry." }, 500);
  }
});