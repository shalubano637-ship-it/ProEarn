
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
    const senderId = userData.user.id;

    const body = await req.json().catch(() => ({}));
    const targetOwnerId = String(body.targetOwnerId ?? "");
    const type = String(body.type ?? "");
    const message = String(body.message ?? "").slice(0, MAX_MESSAGE_LENGTH);
    const targetPostId = String(body.targetPostId ?? "");

    if (!targetOwnerId) return json({ error: "targetOwnerId required" }, 400);
    if (!ALLOWED_TYPES.has(type)) return json({ error: "Invalid type" }, 400);
    if (targetOwnerId === senderId && type !== "chest_ready") return json({ success: true }); // chest_ready is intentionally self-notified

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: targetData } = await admin
      .from("users")
      .select('"pushNotificationsEnabled", "notifyLikes", "notifyComments", "notifyFollow", "notifyMessages", "notifyChestReady", "mutedUsers"')
      .eq("uid", targetOwnerId)
      .maybeSingle();
    if (!targetData) return json({ success: true });

    const pushEnabled = targetData.pushNotificationsEnabled === true;
    if (type === "like" && targetData.notifyLikes === false) return json({ success: true });
    if (type === "comment" && targetData.notifyComments === false) return json({ success: true });
    if (type === "follow" && targetData.notifyFollow === false) return json({ success: true });
    if (type === "message" && targetData.notifyMessages === false) return json({ success: true });
    if (type === "chest_ready" && targetData.notifyChestReady === false) return json({ success: true });
    if (type === "message" && Array.isArray(targetData.mutedUsers) && targetData.mutedUsers.includes(senderId)) {
      return json({ success: true });
    }

    if (type === "message") {
      const { data: presence } = await admin
        .from("user_presence")
        .select("screen, chattingWithUid, updatedAt")
        .eq("uid", targetOwnerId)
        .maybeSingle();

      const activeChat =
        presence?.screen === "chat" &&
        presence?.chattingWithUid?.toString() === senderId &&
        presence?.updatedAt &&
        (Date.now() - new Date(presence.updatedAt).getTime()) < 120000;

      if (activeChat) return json({ success: true });
    }

    const { data: senderData } = await admin
      .from("users")
      .select('"userName", "profileUrl"')
      .eq("uid", senderId)
      .maybeSingle();

    const activeName = senderData?.userName ?? "User";
    const activeProfile = senderData?.profileUrl ?? "";

    if (type !== "message") {
      await admin.from("notifications").insert({
        targetOwnerId,
        type,
        senderId,
        senderName: activeName,
        senderProfile: activeProfile,
        message,
        targetPostId,
      });
    }

    let pushBody = message;
    let pushTitle = "You have a new notification";
    if (type === "like") pushBody = "Someone liked your post";
    else if (type === "follow") pushBody = "Someone started following you";
    else if (type === "comment") pushBody = "Someone commented on your post";
    else if (type === "message") pushBody = "Someone sent you a message";
    else if (type === "chest_ready") { pushTitle = "Chest Ready"; pushBody = "Your chest is ready to open! 🎁"; }

    if (!pushEnabled) return json({ success: true });

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
      console.error("OneSignal push failed:", pushResponse.status, await pushResponse.text());
    }

    return json({ success: true });
  } catch (e) {
    console.error("notify error:", e);
    return json({ error: "Failed to notify" }, 500);
  }
});
