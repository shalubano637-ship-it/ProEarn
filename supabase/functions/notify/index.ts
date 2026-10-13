import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID")!;
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY")!;

const ALLOWED_TYPES = new Set(["like", "comment", "follow", "get", "message", "chest_ready"]);
const MAX_MESSAGE_LENGTH = 300;
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json", "Cache-Control": "no-store" },
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

    const senderId = userData.user.id;
    const body = await req.json().catch(() => ({}));
    const targetOwnerId = String(body.targetOwnerId ?? "");
    const type = String(body.type ?? "");
    const message = String(body.message ?? "").slice(0, MAX_MESSAGE_LENGTH);
    const targetPostId = String(body.targetPostId ?? "");

    if (!targetOwnerId || !ALLOWED_TYPES.has(type)) return json({ error: "Invalid request" }, 400);
    if ((type === "chest_ready" && targetOwnerId !== senderId) ||
        (type !== "chest_ready" && targetOwnerId === senderId)) {
      return json({ success: true });
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    let eventKey = "";

    if (["like", "comment", "get"].includes(type)) {
      if (!/^[0-9a-f-]{36}$/i.test(targetPostId)) return json({ error: "Invalid post" }, 400);
      const { data: post } = await admin.from("posts")
        .select("id,userName,likedBy").eq("id", targetPostId).maybeSingle();
      if (!post || post.userName !== targetOwnerId) return json({ error: "Event not verified" }, 403);

      if (type === "like") {
        if (!Array.isArray(post.likedBy) || !post.likedBy.map(String).includes(senderId)) {
          return json({ error: "Event not verified" }, 403);
        }
        eventKey = targetPostId;
      } else if (type === "comment") {
        const { data: comment } = await admin.from("comments").select("id")
          .eq("postId", targetPostId).eq("userId", senderId)
          .order("timestamp", { ascending: false }).limit(1).maybeSingle();
        if (!comment) return json({ error: "Event not verified" }, 403);
        eventKey = String(comment.id);
      } else {
        const { data: cooldown } = await admin.from("cooldowns").select("unlockTime")
          .eq("postId", targetPostId).eq("userId", senderId)
          .order("unlockTime", { ascending: false }).limit(1).maybeSingle();
        if (!cooldown) return json({ error: "Event not verified" }, 403);
        eventKey = targetPostId + ":" + cooldown.unlockTime;
      }
    } else if (type === "follow") {
      const { data: target } = await admin.from("users").select("followers")
        .eq("uid", targetOwnerId).maybeSingle();
      if (!Array.isArray(target?.followers) || !target.followers.map(String).includes(senderId)) {
        return json({ error: "Event not verified" }, 403);
      }
      eventKey = new Date().toISOString().slice(0, 10);
    } else if (type === "message") {
      const { data: conversation } = await admin.from("conversations").select("id")
        .or("and(participantA.eq." + senderId + ",participantB.eq." + targetOwnerId +
          "),and(participantA.eq." + targetOwnerId + ",participantB.eq." + senderId + ")")
        .limit(1).maybeSingle();
      if (!conversation) return json({ error: "Event not verified" }, 403);

      const { data: recentMessage } = await admin.from("messages").select("id")
        .eq("conversationId", conversation.id).eq("senderId", senderId)
        .eq("deletedForEveryone", false)
        .gte("createdAt", new Date(Date.now() - 120000).toISOString())
        .order("createdAt", { ascending: false }).limit(1).maybeSingle();
      if (!recentMessage) return json({ error: "Event not verified" }, 403);
      eventKey = String(recentMessage.id);
    } else {
      // Client timers can expire while the app is running without setting the
      // persisted isUnlocked flag. unlockAt is authoritative for due chests.
      const now = Date.now();
      const { data: coinChest } = await admin.from("coin_chest_progress")
        .select("currentChestIndex,unlockAt,isUnlocked").eq("uid", senderId).maybeSingle();
      const { data: giftChest } = await admin.from("chest_progress")
        .select("currentChestIndex,unlockAt,isUnlocked").eq("uid", senderId).maybeSingle();

      const isDue = (row: any) => !!row && (
        row.isUnlocked === true ||
        (row.unlockAt != null && Date.parse(String(row.unlockAt)) <= now)
      );
      const readyChest = isDue(coinChest) ? coinChest : isDue(giftChest) ? giftChest : null;
      if (!readyChest) return json({ error: "Chest not ready" }, 403);

      eventKey = String(readyChest.currentChestIndex) + ":" + String(readyChest.unlockAt);
    }

    const { error: dedupError } = await admin.from("notification_delivery_dedup").insert({
      senderId,
      targetOwnerId,
      type,
      eventKey,
    });
    if (dedupError) {
      if (dedupError.code === "23505") return json({ success: true });
      console.error("notification dedup insert failed", dedupError);
      return json({ error: "Unavailable" }, 503);
    }

    const { data: targetPrefs } = await admin.from("users")
      .select('pushNotificationsEnabled,notifyLikes,notifyComments,notifyFollow,notifyMessages,notifyChestReady,mutedUsers')
      .eq("uid", targetOwnerId).maybeSingle();
    if (!targetPrefs) return json({ success: true });

    if ((type === "like" && targetPrefs.notifyLikes === false) ||
        (type === "comment" && targetPrefs.notifyComments === false) ||
        (type === "follow" && targetPrefs.notifyFollow === false) ||
        (type === "message" && targetPrefs.notifyMessages === false) ||
        (type === "chest_ready" && targetPrefs.notifyChestReady === false) ||
        (type === "message" && Array.isArray(targetPrefs.mutedUsers) &&
          targetPrefs.mutedUsers.map(String).includes(senderId))) {
      return json({ success: true });
    }

    const { data: sender } = await admin.from("users").select('userName,profileUrl')
      .eq("uid", senderId).maybeSingle();

    if (type !== "message") {
      const { error: notificationError } = await admin.from("notifications").insert({
        targetOwnerId,
        type,
        senderId,
        senderName: sender?.userName ?? "User",
        senderProfile: sender?.profileUrl ?? "",
        message: message || (type === "chest_ready" ? "Your chest is ready to open! 🎁" : ""),
        targetPostId: targetPostId || null,
      });
      if (notificationError) {
        console.error("notification row insert failed", notificationError);
        return json({ error: "Could not save notification" }, 503);
      }
    }

    if (targetPrefs.pushNotificationsEnabled !== true) return json({ success: true });

    const pushTitle = type === "chest_ready" ? "Chest Ready" : "You have a new notification";
    const pushBody = type === "like" ? "Someone liked your post" :
      type === "comment" ? "Someone commented on your post" :
      type === "follow" ? "Someone started following you" :
      type === "get" ? "Someone got your post" :
      type === "message" ? "Someone sent you a message" :
      "Your chest is ready to open! 🎁";

    const pushResponse = await fetch("https://onesignal.com/api/v1/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Authorization": `Key ${ONESIGNAL_REST_API_KEY}`,
      },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        target_channel: "push",
        include_aliases: { external_id: [targetOwnerId] },
        headings: { en: pushTitle },
        contents: { en: pushBody },
        data: { type, senderId, targetPostId },
        priority: 10,
      }),
    });
    if (!pushResponse.ok) {
      const errorBody = await pushResponse.text();
      console.error("OneSignal push failed:", pushResponse.status, errorBody);
      return json({ success: false, pushError: "OneSignal delivery failed" }, 502);
    }
    return json({ success: true });
  } catch (error) {
    console.error("notify error:", error);
    return json({ error: "Failed to notify" }, 500);
  }
});
