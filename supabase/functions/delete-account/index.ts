import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);
  const uid = userData.user.id;

  try {
    await admin.from("messages").delete().eq("senderId", uid);

    const { data: conversations } = await admin
      .from("conversations")
      .select("id")
      .or(`participantA.eq.${uid},participantB.eq.${uid}`);
    const conversationIds = (conversations ?? []).map((row) => row.id).filter(Boolean);
    if (conversationIds.length) {
      await admin.from("messages").delete().in("conversationId", conversationIds);
      await admin.from("conversations").delete().in("id", conversationIds);
    }

    const { data: posts } = await admin.from("posts").select("id").eq("userName", uid);
    const postIds = (posts ?? []).map((row) => row.id).filter(Boolean);
    if (postIds.length) {
      await admin.from("comments").delete().in("postId", postIds);
      await admin.from("cooldowns").delete().in("postId", postIds);
      await admin.from("gift_received_log").delete().in("postId", postIds);
      await admin.from("posts").delete().in("id", postIds);
    }

    await admin.from("comments").delete().eq("userId", uid);
    await admin.from("gift_inventory").delete().eq("ownerUid", uid);
    await admin.from("gift_received_log").delete().or(`fromUid.eq.${uid},recipientUid.eq.${uid}`);
    await admin.from("notifications").delete().eq("targetOwnerId", uid);
    await admin.from("user_presence").delete().eq("uid", uid);
    await admin.from("daily_get_counts").delete().eq("uid", uid);
    await admin.from("daily_popularity_counts").delete().eq("uid", uid);
    await admin.from("chest_progress").delete().eq("uid", uid);
    await admin.from("email_otps").delete().eq("userId", uid);
    await admin.from("reports").delete().or(`reportedBy.eq.${uid},reportedUserId.eq.${uid}`);

    const { error: profileError } = await admin.from("users").delete().eq("uid", uid);
    if (profileError) throw profileError;

    const { error: authDeleteError } = await admin.auth.admin.deleteUser(uid);
    if (authDeleteError) throw authDeleteError;

    return json({ success: true });
  } catch (error) {
    console.error("delete-account failed", error);
    return json({ error: "Account deletion could not be completed" }, 500);
  }
});
