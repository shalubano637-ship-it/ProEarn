import { createClient } from "npm:@supabase/supabase-js@2";
import { cert, getApps, initializeApp } from "npm:firebase-admin@13.2.0/app";
import { getAuth } from "npm:firebase-admin@13.2.0/auth";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json", "cache-control": "no-store" } });
}
function firebaseAdminAuth() {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("Firebase Admin service account is not configured");
  const serviceAccount = JSON.parse(raw);
  if (serviceAccount.project_id !== "proearn-6acdd") throw new Error("Firebase project mismatch");
  const app = getApps()[0] ?? initializeApp({ credential: cert(serviceAccount), projectId: serviceAccount.project_id });
  return getAuth(app);
}
const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!supabaseUrl || !serviceRoleKey || !Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")) return json({ error: "Deletion service is not configured" }, 503);

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Please sign in again before requesting deletion." }, 401);

  let user: { uid: string; email?: string; emailVerified?: boolean };
  try {
    const auth = firebaseAdminAuth();
    const decoded = await auth.verifyIdToken(authorization.slice(7), true);
    if (decoded.role !== "authenticated" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(decoded.uid)) {
      return json({ error: "Your sign-in session is invalid. Please sign in again." }, 401);
    }
    const firebaseUser = await auth.getUser(decoded.uid);
    if (firebaseUser.disabled || !firebaseUser.email || !firebaseUser.emailVerified) {
      return json({ error: "Please verify your account email before requesting deletion." }, 403);
    }
    user = { uid: firebaseUser.uid, email: firebaseUser.email, emailVerified: firebaseUser.emailVerified };
  } catch (error) {
    console.error("Firebase token verification failed for deletion request", error);
    return json({ error: "Your sign-in session has expired. Please sign in again." }, 401);
  }

  const body = await request.json().catch(() => ({}));
  const submittedEmail = String(body.email ?? "").trim().toLowerCase();
  const verifiedEmail = user.email!.trim().toLowerCase();
  if (!submittedEmail || submittedEmail !== verifiedEmail) return json({ error: "The verified email does not match this account." }, 403);

  const cutoff = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const { data: recentRequest, error: recentError } = await admin.from("account_deletion_requests")
    .select("id,status").eq("request_key", user.uid).gt("created_at", cutoff)
    .order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (recentError) {
    console.error("Could not inspect recent deletion requests", recentError);
    return json({ error: "Could not start the deletion request." }, 500);
  }
  if (recentRequest?.status === "processing") return json({ error: "A deletion request is already being processed." }, 429);

  let deletionRequest: { id: string } | null = null;
  if (recentRequest?.id && recentRequest.status === "failed") {
    const { data, error } = await admin.from("account_deletion_requests").update({
      email: verifiedEmail, reason: String(body.reason ?? "").slice(0, 1000), status: "processing", processed_at: null,
    }).eq("id", recentRequest.id).select("id").single();
    if (error) {
      console.error("Could not retry deletion request", error);
      return json({ error: "Could not retry the deletion request." }, 500);
    }
    deletionRequest = data;
  } else {
    const { data, error } = await admin.from("account_deletion_requests").insert({
      email: verifiedEmail, reason: String(body.reason ?? "").slice(0, 1000), status: "processing", request_key: user.uid,
    }).select("id").single();
    if (error) {
      console.error("Could not record verified deletion request", error);
      return json({ error: "Could not record the deletion request." }, 500);
    }
    deletionRequest = data;
  }
  if (!deletionRequest) return json({ error: "Could not start the deletion request." }, 500);

  const deleteResponse = await fetch(`${supabaseUrl}/functions/v1/delete-account`, {
    method: "POST",
    headers: { Authorization: authorization, apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? "", "content-type": "application/json" },
    body: "{}",
  });
  if (!deleteResponse.ok) {
    await admin.from("account_deletion_requests").update({ status: "failed" }).eq("id", deletionRequest.id);
    const detail = await deleteResponse.text().catch(() => "");
    console.error("Firebase account deletion failed", deleteResponse.status, detail.slice(0, 300));
    return json({ error: "Deletion could not be completed. Your account remains active. Please retry or contact support." }, 500);
  }

  const { error: completeError } = await admin.from("account_deletion_requests").update({
    status: "completed", processed_at: new Date().toISOString(), email: "deleted-account@invalid",
    reason: "", request_key: `completed:${deletionRequest.id}`,
  }).eq("id", deletionRequest.id);
  if (completeError) console.error("Account deleted but request audit status update failed", completeError);
  return json({ success: true });
});