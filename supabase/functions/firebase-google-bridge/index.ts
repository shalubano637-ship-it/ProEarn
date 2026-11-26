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

async function keyedHash(value: string, pepper: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(pepper), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return Array.from(new Uint8Array(signature), (b) => b.toString(16).padStart(2, "0")).join("");
}

function adminAuth() {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("Firebase Admin service account is not configured");
  const serviceAccount = JSON.parse(raw);
  if (serviceAccount.project_id !== "proearn-6acdd") throw new Error("Firebase project mismatch");
  const app = getApps()[0] ?? initializeApp({ credential: cert(serviceAccount), projectId: serviceAccount.project_id });
  return getAuth(app);
}

function makeReferralCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(bytes, (b) => (b % 36).toString(36)).join("").toUpperCase();
}

function safeUsername(email: string) {
  const base = email.split("@")[0].toLowerCase().replace(/[^a-z0-9_.]/g, "").slice(0, 20) || "user";
  return base.length >= 3 ? base : `user_${base}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const body = await req.json();
    const idToken = typeof body.googleIdToken === "string" ? body.googleIdToken : "";
    const termsAcceptedAt = typeof body.termsAcceptedAt === "string" ? body.termsAcceptedAt : "";
    const termsVersion = typeof body.termsVersion === "string" ? body.termsVersion : "";
    if (!idToken || idToken.length > 10000) return json({ error: "Google credential is missing." }, 400);
    if (!termsAcceptedAt || !termsVersion) return json({ error: "Terms acceptance is required." }, 400);

    const expectedAudience = Deno.env.get("GOOGLE_WEB_CLIENT_ID") ?? "449305618154-ii2bo0jsf8ner0oa4f6lv4eo3q4slft0.apps.googleusercontent.com";
    if (!expectedAudience) return json({ error: "Google sign-in is not configured on the server." }, 503);

    // Validate the Google-issued ID token server-side. Never trust client-supplied email.
    const verifyResponse = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`);
    if (!verifyResponse.ok) return json({ error: "Google credential could not be verified." }, 401);
    const claims = await verifyResponse.json();
    const issuer = claims.iss;
    if (claims.aud !== expectedAudience ||
        !["accounts.google.com", "https://accounts.google.com"].includes(issuer) ||
        claims.email_verified !== "true" ||
        !claims.email ||
        Number(claims.exp) <= Math.floor(Date.now() / 1000)) {
      return json({ error: "Google credential is invalid or not verified." }, 401);
    }

    const email = String(claims.email).trim().toLowerCase();
    const auth = adminAuth();
    const serviceUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!serviceUrl || !serviceKey) throw new Error("Supabase server configuration is missing");
    const db = createClient(serviceUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const ip = req.headers.get("cf-connecting-ip") ?? req.headers.get("x-real-ip") ??
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
    const emailKey = await keyedHash(`email:${email}`, serviceKey);
    const ipKey = await keyedHash(`ip:${ip}`, serviceKey);
    const { data: allowed, error: rateError } = await db.rpc("consume_firebase_signup_rate_limit", {
      p_email_key: emailKey, p_ip_key: ipKey,
    });
    if (rateError) throw rateError;
    if (allowed !== true) return json({ error: "Too many sign-in attempts. Please try again later." }, 429);

    let firebaseUser;
    let isNewUser = false;
    try {
      firebaseUser = await auth.getUserByEmail(email);
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(firebaseUser.uid)) {
        return json({ error: "This account does not have a compatible UUID identity. Contact support." }, 409);
      }
    } catch (error) {
      if ((error as { code?: string }).code !== "auth/user-not-found") throw error;
      const uid = crypto.randomUUID();
      const username = safeUsername(email);
      isNewUser = true;
      firebaseUser = await auth.createUser({
        uid, email, emailVerified: true, displayName: username, disabled: false,
      });

      let referralCode = "";
      for (let attempt = 0; attempt < 8; attempt++) {
        const candidate = makeReferralCode();
        const { data, error: lookupError } = await db.from("users").select("uid").eq("referralCode", candidate).limit(1);
        if (lookupError) throw lookupError;
        if (!data?.length) { referralCode = candidate; break; }
      }
      if (!referralCode) throw new Error("Could not allocate referral code");

      const { error: insertError } = await db.from("users").insert({
        uid, userName: username, email, fullName: username,
        termsAcceptedAt, termsVersion, referralCode, isEmailVerified: true,
        profileSetupCompleted: false,
      });
      if (insertError) {
        try { await auth.deleteUser(uid); } catch (_) { /* rollback best effort */ }
        throw insertError;
      }
    }

    // The Google ID token above has been verified by Google's tokeninfo endpoint,
    // including email_verified=true and the expected OAuth audience. Sync that
    // verified identity to Firebase even for accounts created before this bridge.
    firebaseUser = await auth.updateUser(firebaseUser.uid, { emailVerified: true });

    // Existing Firebase identities may predate their public profile row. Create
    // a gated starter row only when it is genuinely missing; existing profiles
    // are never reset or forced through onboarding again.
    const { data: profile, error: profileLookupError } = await db
      .from("users")
      .select("uid,profileSetupCompleted")
      .eq("uid", firebaseUser.uid)
      .maybeSingle();
    if (profileLookupError) throw profileLookupError;
    if (profile) {
      const { error: verifiedProfileError } = await db.from("users")
        .update({ isEmailVerified: true })
        .eq("uid", firebaseUser.uid);
      if (verifiedProfileError) throw verifiedProfileError;
    }

    let needsProfileSetup = profile?.profileSetupCompleted === false;
    if (!profile) {
      const username = safeUsername(email);
      const { error: profileInsertError } = await db.from("users").insert({
        uid: firebaseUser.uid,
        userName: username,
        email,
        fullName: username,
        termsAcceptedAt,
        termsVersion,
        isEmailVerified: true,
        profileSetupCompleted: false,
      });
      if (profileInsertError) throw profileInsertError;
      needsProfileSetup = true;
      isNewUser = true;
    }

    await auth.setCustomUserClaims(firebaseUser.uid, { ...(firebaseUser.customClaims ?? {}), role: "authenticated" });
    const customToken = await auth.createCustomToken(firebaseUser.uid, { role: "authenticated" });
    return json({ success: true, customToken, uid: firebaseUser.uid, isNewUser, needsProfileSetup });
  } catch (error) {
    console.error("firebase-google-bridge failed:", error);
    return json({ error: "Google sign-in could not be completed. Please try again." }, 500);
  }
});
