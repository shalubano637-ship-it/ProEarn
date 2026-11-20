import { createClient } from "npm:@supabase/supabase-js@2";
import { cert, getApps, initializeApp } from "npm:firebase-admin@13.2.0/app";
import { getAuth } from "npm:firebase-admin@13.2.0/auth";

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

function requiredString(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function referralCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(bytes, (b) => (b % 36).toString(36)).join("").toUpperCase();
}

async function keyedHash(value: string, pepper: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(pepper),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return Array.from(new Uint8Array(signature), (b) => b.toString(16).padStart(2, "0")).join("");
}

function firebaseAdmin() {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("Firebase Admin service account is not configured");
  const serviceAccount = JSON.parse(raw);
  const projectId = serviceAccount.project_id;
  if (projectId !== "proearn-6acdd") throw new Error("Firebase project mismatch");
  const app = getApps()[0] ?? initializeApp({ credential: cert(serviceAccount), projectId });
  return getAuth(app);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let createdUid: string | null = null;
  try {
    const body = await req.json();
    const email = requiredString(body.email, 254).toLowerCase();
    const password = typeof body.password === "string" ? body.password : "";
    const username = requiredString(body.username, 30);
    const acceptedAt = requiredString(body.termsAcceptedAt, 64);
    const termsVersion = requiredString(body.termsVersion, 40);
    const suppliedReferral = requiredString(body.referralCode, 12).toUpperCase();

    if (!/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(email)) return json({ error: "Enter a valid email address." }, 400);
    if (password.length < 8 || password.length > 128) return json({ error: "Password must be 8–128 characters." }, 400);
    if (!/^[A-Za-z0-9_.]{3,30}$/.test(username)) return json({ error: "Username must be 3–30 letters, numbers, dots or underscores." }, 400);
    if (!acceptedAt || !termsVersion) return json({ error: "Terms acceptance is required." }, 400);

    const serviceUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!serviceUrl || !serviceKey) throw new Error("Supabase server configuration is missing");
    const db = createClient(serviceUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

    // Use only the edge proxy's client-IP headers; never trust arbitrary request body values.
    const ip = req.headers.get("cf-connecting-ip") ??
      req.headers.get("x-real-ip") ??
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      "unknown";
    const emailKey = await keyedHash(`email:${email}`, serviceKey);
    const ipKey = await keyedHash(`ip:${ip}`, serviceKey);
    const { data: allowed, error: rateError } = await db.rpc("consume_firebase_signup_rate_limit", {
      p_email_key: emailKey,
      p_ip_key: ipKey,
    });
    if (rateError) throw rateError;
    if (allowed !== true) return json({ error: "Too many signup attempts. Please try again later." }, 429);

    const auth = firebaseAdmin();
    const { data: usernameTaken, error: usernameError } = await db.from("users")
      .select("uid").ilike("userName", username).limit(1);
    if (usernameError) throw usernameError;
    if (usernameTaken?.length) return json({ error: "That username is already taken." }, 409);

    let referredBy: string | null = null;
    if (suppliedReferral) {
      const { data: referrer, error } = await db.from("users")
        .select("uid").eq("referralCode", suppliedReferral).maybeSingle();
      if (error) throw error;
      if (!referrer) return json({ error: "Referral code is invalid." }, 400);
      referredBy = String(referrer.uid);
    }

    const uid = crypto.randomUUID();
    const created = await auth.createUser({
      uid,
      email,
      password,
      emailVerified: false,
      displayName: username,
      disabled: false,
    });
    createdUid = created.uid;
    await auth.setCustomUserClaims(createdUid, { role: "authenticated" });

    let ownReferralCode = "";
    for (let attempt = 0; attempt < 8; attempt++) {
      const candidate = referralCode();
      const { data, error } = await db.from("users").select("uid")
        .eq("referralCode", candidate).limit(1);
      if (error) throw error;
      if (!data?.length) { ownReferralCode = candidate; break; }
    }
    if (!ownReferralCode) throw new Error("Could not allocate referral code");

    const { error: insertError } = await db.from("users").insert({
      uid: createdUid,
      userName: username,
      email,
      fullName: username,
      termsAcceptedAt: acceptedAt,
      termsVersion,
      referralCode: ownReferralCode,
      referredBy,
      isEmailVerified: false,
    });
    if (insertError) throw insertError;

    return json({ success: true, uid: createdUid, email, emailVerified: false });
  } catch (error) {
    if (createdUid) {
      try { await firebaseAdmin().deleteUser(createdUid); } catch (_) { /* best-effort rollback */ }
    }
    const message = error instanceof Error ? error.message : "Signup failed";
    const duplicate = /email.*already|already.*email|email-already-exists/i.test(message);
    console.error("firebase-auth-provision:", message);
    return json({ error: duplicate ? "An account with this email already exists." : "Account creation failed. Please try again." }, duplicate ? 409 : 500);
  }
});
