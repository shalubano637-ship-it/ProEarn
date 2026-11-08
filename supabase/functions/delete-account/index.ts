import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const mediaGatewayUrl = Deno.env.get("MEDIA_GATEWAY_URL") ?? "";
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

async function deleteWhere(table: string, column: string, value: string) {
  const { error } = await admin.from(table).delete().eq(column, value);
  assertNoError(`Delete ${table} by ${column}`, error);
}

async function removeUserReferences(uid: string) {
  let offset = 0;
  const pageSize = 500;
  while (true) {
    const { data, error } = await admin
      .from("users")
      .select("uid,followers,following,blockedUsers,hiddenPosts,mutedUsers,referredBy")
      .neq("uid", uid)
      .order("uid", { ascending: true })
      .range(offset, offset + pageSize - 1);
    assertNoError("Read user references", error);
    const rows = data ?? [];
    for (let i = 0; i < rows.length; i += 20) {
      await Promise.all(rows.slice(i, i + 20).map(async (row: Record<string, unknown>) => {
        const patch: Record<string, unknown> = {};
        for (const field of ["followers", "following", "blockedUsers", "hiddenPosts", "mutedUsers"]) {
          const value = row[field];
          if (Array.isArray(value) && value.includes(uid)) {
            patch[field] = value.filter((entry) => entry !== uid);
          }
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
  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    return json({ error: "Account deletion service is not configured" }, 503);
  }

  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) return json({ error: "Unauthorized" }, 401);

  const uid = authData.user.id;
  try {
    // Remove non-FK content first. Every operation is checked and safe to retry
    // if a later step fails.
    const { error: commentError } = await admin.from("comments").delete().eq("userId", uid);
    assertNoError("Delete user's comments", commentError);

    const { error: postError } = await admin.from("posts").delete().eq("userName", uid);
    assertNoError("Delete user's posts", postError);

    const { data: conversations, error: conversationReadError } = await admin
      .from("conversations")
      .select("id")
      .or(`participantA.eq.${uid},participantB.eq.${uid}`);
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
    await deleteWhere("notifications", "senderId", uid);
    await deleteWhere("notification_delivery_dedup", "senderId", uid);
    await deleteWhere("notification_delivery_dedup", "targetOwnerId", uid);
    await deleteWhere("follow_action_log", "actorUid", uid);
    await deleteWhere("ad_gift_claims", "uid", uid);
    await deleteWhere("daily_like_counts", "uid", uid);

    // Preserve moderation history while removing the deleted account's identity.
    const { error: reportError } = await admin
      .from("reports")
      .update({ reportedBy: "deleted-user", reportedUserId: null })
      .or(`reportedBy.eq.${uid},reportedUserId.eq.${uid}`);
    assertNoError("Anonymize moderation reports", reportError);

    await removeUserReferences(uid);

    if (!mediaGatewayUrl || !mediaInternalToken) {
      throw new Error("Media deletion service is not configured");
    }
    const mediaResponse = await fetch(
      `${mediaGatewayUrl.replace(/\/$/, "")}/internal/delete-user-media`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-internal-token": mediaInternalToken,
        },
        body: JSON.stringify({ userId: uid }),
      },
    );
    if (!mediaResponse.ok) {
      const detail = await mediaResponse.text().catch(() => "");
      throw new Error(`Media deletion failed (HTTP ${mediaResponse.status}): ${detail.slice(0, 200)}`);
    }

    // This FK cascades the profile and remaining relational rows. Clear
    // users.referredBy above to avoid the self-reference NO ACTION constraint.
    // Delete Auth last so failure leaves the user able to retry.
    const email = authData.user.email?.toLowerCase();
    if (email) {
      const { error: adminCleanupError } = await admin.from("admins").delete().eq("email", email);
      assertNoError("Remove admin mapping", adminCleanupError);
    }
    const { error: authDeleteError } = await admin.auth.admin.deleteUser(uid);
    assertNoError("Delete authentication account", authDeleteError);

    return json({ success: true, mediaDeleted: true });
  } catch (error) {
    console.error("delete-account failed", { userId: uid, error });
    return json({
      error: "Account deletion could not be completed. Your sign-in remains available so you can retry.",
    }, 500);
  }
});
