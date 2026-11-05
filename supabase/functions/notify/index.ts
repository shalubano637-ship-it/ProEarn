import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const ALLOWED_TYPES = new Set(["like", "comment", "follow", "get", "message", "chest_ready"]);
const MAX_MESSAGE_LENGTH = 300;

const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL") ?? "";
const FIREBASE_PRIVATE_KEY = Deno.env.get("FIREBASE_PRIVATE_KEY") ?? "";
let cachedAccessToken = "";
let cachedAccessTokenExpiry = 0;

function b64url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
function pemBytes(pem: string): Uint8Array {
  const normalized = pem.replace(/\\n/g, "\n").replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----/g, "").replace(/\s/g, "");
  const raw = atob(normalized);
  return Uint8Array.from(raw, c => c.charCodeAt(0));
}
async function firebaseAccessToken(): Promise<string> {
  if (cachedAccessToken && Date.now() < cachedAccessTokenExpiry - 60000) return cachedAccessToken;
  if (!FIREBASE_PROJECT_ID || !FIREBASE_CLIENT_EMAIL || !FIREBASE_PRIVATE_KEY) {
    throw new Error("Firebase secrets missing");
  }
  const now = Math.floor(Date.now() / 1000);
  const unsigned = b64url(JSON.stringify({alg:"RS256",typ:"JWT"})) + "." +
    b64url(JSON.stringify({
      iss:FIREBASE_CLIENT_EMAIL,
      scope:"https://www.googleapis.com/auth/firebase.messaging",
      aud:"https://oauth2.googleapis.com/token",
      iat:now,
      exp:now+3600
    }));
  const key = await crypto.subtle.importKey(
    "pkcs8", pemBytes(FIREBASE_PRIVATE_KEY),
    {name:"RSASSA-PKCS1-v1_5",hash:"SHA-256"}, false, ["sign"]
  );
  const sig = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)
  ));
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method:"POST",
    headers:{"Content-Type":"application/x-www-form-urlencoded"},
    body:new URLSearchParams({
      grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion:unsigned+"."+b64url(sig)
    })
  });
  if (!response.ok) throw new Error("Google OAuth token request failed: "+response.status);
  const result = await response.json();
  cachedAccessToken = String(result.access_token ?? "");
  cachedAccessTokenExpiry = Date.now() + Number(result.expires_in ?? 3600)*1000;
  if (!cachedAccessToken) throw new Error("Google OAuth token missing");
  return cachedAccessToken;
}
async function sendFcm(token: string, title: string, body: string, data: Record<string,string>) {
  const access = await firebaseAccessToken();
  return await fetch("https://fcm.googleapis.com/v1/projects/"+FIREBASE_PROJECT_ID+"/messages:send", {
    method:"POST",
    headers:{Authorization:"Bearer "+access,"Content-Type":"application/json"},
    body:JSON.stringify({message:{
      token,
      notification:{title,body},
      data,
      android:{priority:"HIGH"}
    }})
  });
}

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
    const body = await req.json().catch(() => ({}));
    const targetOwnerId = String(body.targetOwnerId ?? "");
    const type = String(body.type ?? "");
    // The scheduled database job may invoke this same function for chest_ready only.
    // It must present the server-only secret; normal notification types still require a user JWT.
    const cronSecret = Deno.env.get("CHEST_CRON_SECRET") ?? "";
    const cronChestCall = type === "chest_ready" && cronSecret.length > 0 &&
      req.headers.get("x-cron-secret") === cronSecret;
    let senderId = "";
    if (cronChestCall) {
      if (!/^[0-9a-f-]{36}$/i.test(targetOwnerId)) return json({ error: "Invalid target" }, 400);
      senderId = targetOwnerId;
    } else {
      const authHeader = req.headers.get("Authorization") ?? "";
      const authed = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: authHeader } },
      });
      const { data: userData, error: authError } = await authed.auth.getUser();
      if (authError || !userData?.user) return json({ error: "Unauthorized" }, 401);
      senderId = userData.user.id;
    }
    const message = String(body.message ?? "").slice(0, MAX_MESSAGE_LENGTH);
    const targetPostId = String(body.targetPostId ?? "");

    if (!targetOwnerId || !ALLOWED_TYPES.has(type)) return json({ error: "Invalid request" }, 400);
    if ((type === "chest_ready" && targetOwnerId !== senderId) ||
        (type !== "chest_ready" && targetOwnerId === senderId)) {
      return json({ success: true });
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    let eventKey = "";
    let chestProgressTable: "chest_progress" | null = null;

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
      const { data: giftChest } = await admin.from("chest_progress")
        .select("currentChestIndex,unlockAt,pushSentAt")
        .eq("uid", senderId).maybeSingle();

      const giftChestDue = !!giftChest && giftChest.unlockAt != null &&
        Date.parse(String(giftChest.unlockAt)) <= Date.now();
      if (!giftChestDue) return json({ error: "Gift chest timer not finished" }, 403);
      if (giftChest.pushSentAt != null) return json({ success: true, alreadyPushed: true });

      chestProgressTable = "chest_progress";
      eventKey = String(giftChest.currentChestIndex) + ":" + String(giftChest.unlockAt);
    }

    const { error: dedupError } = await admin.from("notification_delivery_dedup").insert({
      senderId,
      targetOwnerId,
      type,
      eventKey,
    });
    if (dedupError) {
      // The chest cron may have reserved this event while only writing the
      // in-app notification. That reservation must not suppress OneSignal push.
      if (dedupError.code === "23505" && type !== "chest_ready") return json({ success: true });
      if (dedupError.code !== "23505") {
        console.error("notification dedup insert failed", dedupError);
        return json({ error: "Unavailable" }, 503);
      }
    }

    const { data: targetPrefs } = await admin.from("users")
      .select('pushNotificationsEnabled,notifyLikes,notifyComments,notifyFollow,notifyMessages,notifyChestReady,mutedUsers')
      .eq("uid", targetOwnerId).maybeSingle();
    if (!targetPrefs) return json({ success: true });

    if ((type === "like" && targetPrefs.notifyLikes === false) ||
        (type === "comment" && targetPrefs.notifyComments === false) ||
        (type === "follow" && targetPrefs.notifyFollow === false) ||
        (type === "message" && targetPrefs.notifyMessages === false) ||
        (type === "message" && Array.isArray(targetPrefs.mutedUsers) &&
          targetPrefs.mutedUsers.map(String).includes(senderId))) {
      return json({ success: true });
    }

    // Suppress message push when recipient is actively viewing this exact chat.
    // The chat screen refreshes presence every 30 seconds; stale rows are ignored.
    if (type === "message") {
      const activeSince = new Date(Date.now() - 90000).toISOString();
      const { data: presence, error: presenceError } = await admin.from("user_presence")
        .select('uid,screen,chattingWithUid,updatedAt')
        .eq("uid", targetOwnerId)
        .eq("screen", "chat")
        .eq("chattingWithUid", senderId)
        .gte("updatedAt", activeSince)
        .maybeSingle();
      if (presenceError) {
        console.error("chat presence lookup failed:", presenceError);
      } else if (presence) {
        return json({ success: true, pushSuppressed: true, reason: "recipient_in_chat" });
      }
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
        targetPostId: targetPostId || "",
      });
      if (notificationError) {
        console.error("notification row insert failed", notificationError);
        // Release the dedup reservation when the in-app notification was not
        // saved, so a client retry can attempt the event again.
        const { error: releaseError } = await admin.from("notification_delivery_dedup")
          .delete()
          .eq("senderId", senderId)
          .eq("targetOwnerId", targetOwnerId)
          .eq("type", type)
          .eq("eventKey", eventKey);
        if (releaseError) {
          console.error("notification dedup release failed", releaseError);
        }
        return json({ error: "Could not save notification" }, 503);
      }
    }

    // Keep the in-app chest notification even when chest push notifications are disabled.
    // This preference controls FCM delivery, not the Notifications inbox.
    if (targetPrefs.pushNotificationsEnabled !== true ||
        (type === "chest_ready" && targetPrefs.notifyChestReady === false)) {
      return json({ success: true });
    }

    const pushTitle = type === "chest_ready" ? "Chest Ready" : "You have a new notification";
    const pushBody = type === "like" ? "Someone liked your post" :
      type === "comment" ? "Someone commented on your post" :
      type === "follow" ? "Someone started following you" :
      type === "get" ? "Someone got your post" :
      type === "message" ? "Someone sent you a message" :
      "Your chest is ready to open! 🎁";

    const { data: recipient } = await admin.from("users").select("fcmToken")
      .eq("uid", targetOwnerId).maybeSingle();
    const fcmToken = String(recipient?.fcmToken ?? "").trim();
    let fcmDelivered = false;
    if (fcmToken) {
      try {
        const fcmResponse = await sendFcm(fcmToken, pushTitle, pushBody, {type,senderId,targetPostId});
        if (fcmResponse.ok) {
          fcmDelivered = true;
        } else {
          const error = await fcmResponse.json().catch(() => ({}));
          const errorCode = String(error?.error?.details?.[0]?.errorCode ?? "");
          console.error("FCM delivery failed:", fcmResponse.status, errorCode || "provider_error");
          if (errorCode === "UNREGISTERED" || fcmResponse.status === 404) {
            await admin.from("users").update({fcmToken:null}).eq("uid",targetOwnerId);
          }
        }
      } catch (error) {
        console.error("FCM send failed:", error instanceof Error ? error.message : "unknown");
      }
    } else {
      console.warn("FCM push skipped: recipient has no registered device token.");
    }
    if (type === "chest_ready" && chestProgressTable != null) {

      const { error: markPushError } = await admin.from(chestProgressTable)
        .update({ pushSentAt: new Date().toISOString() })
        .eq("uid", senderId)
        .is("pushSentAt", null);
      if (markPushError) console.error("Could not persist chest push delivery marker:", markPushError);
    }
    return json({ success: true });
  } catch (error) {
    console.error("notify error:", error);
    return json({ error: "Failed to notify" }, 500);
  }
});
