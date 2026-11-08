import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
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

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    return json({ error: "Deletion service is not configured" }, 503);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Email verification required" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  const user = authData.user;
  if (authError || !user || !user.email || !user.email_confirmed_at) {
    return json({ error: "Please verify ownership of your account email first" }, 401);
  }

  const body = await request.json().catch(() => ({}));
  const submittedEmail = String(body.email ?? "").trim().toLowerCase();
  const verifiedEmail = user.email.trim().toLowerCase();
  if (!submittedEmail || submittedEmail !== verifiedEmail) {
    return json({ error: "The verified email does not match this account" }, 403);
  }

  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data: recentRequest, error: recentError } = await admin
    .from("account_deletion_requests")
    .select("id,status")
    .eq("request_key", user.id)
    .gt("created_at", cutoff)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (recentError) {
    console.error("Could not inspect recent deletion requests", recentError);
    return json({ error: "Could not start the deletion request" }, 500);
  }
  if (recentRequest?.status === "processing") {
    return json({ error: "A deletion request is already being processed" }, 429);
  }

  let deletionRequest: { id: string } | null = null;
  if (recentRequest?.id && recentRequest.status === "failed") {
    const { data, error } = await admin
      .from("account_deletion_requests")
      .update({
        email: verifiedEmail,
        reason: String(body.reason ?? "").slice(0, 1000),
        status: "processing",
        processed_at: null,
      })
      .eq("id", recentRequest.id)
      .select("id")
      .single();
    if (error) {
      console.error("Could not retry deletion request", error);
      return json({ error: "Could not retry the deletion request" }, 500);
    }
    deletionRequest = data;
  } else {
    const { data, error } = await admin
      .from("account_deletion_requests")
      .insert({
        email: verifiedEmail,
        reason: String(body.reason ?? "").slice(0, 1000),
        status: "processing",
        request_key: user.id,
      })
      .select("id")
      .single();
    if (error) {
      console.error("Could not record verified deletion request", error);
      return json({ error: "Could not record the verified deletion request" }, 500);
    }
    deletionRequest = data;
  }
  if (!deletionRequest) return json({ error: "Could not start the deletion request" }, 500);

  const deleteResponse = await fetch(`${supabaseUrl}/functions/v1/delete-account`, {
    method: "POST",
    headers: {
      Authorization: authorization,
      apikey: anonKey,
      "content-type": "application/json",
    },
    body: "{}",
  });
  if (!deleteResponse.ok) {
    const { error: updateError } = await admin
      .from("account_deletion_requests")
      .update({ status: "failed" })
      .eq("id", deletionRequest.id);
    if (updateError) console.error("Could not mark deletion request failed", updateError);
    const detail = await deleteResponse.text().catch(() => "");
    console.error("Verified account deletion failed", deleteResponse.status, detail.slice(0, 300));
    return json({ error: "Deletion could not be completed. Please retry or contact support." }, 500);
  }

  const { error: completeError } = await admin
    .from("account_deletion_requests")
    .update({
      status: "completed",
      processed_at: new Date().toISOString(),
      email: "deleted-account@invalid",
      reason: "",
      request_key: `completed:${deletionRequest.id}`,
    })
    .eq("email", verifiedEmail);
  if (completeError) {
    // Account is already deleted. Keep this operational warning for reconciliation.
    console.error("Account deleted but request audit status update failed", completeError);
  }
  return json({ success: true });
});
