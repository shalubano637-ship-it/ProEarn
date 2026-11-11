import { createClient } from "npm:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PACKAGE = Deno.env.get("GOOGLE_PLAY_PACKAGE_NAME") ?? "com.prosn.app";
const ACCOUNT_JSON = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON") ?? "";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const COINS: Record<string, number> = {
  coins_100: 100, coins_275: 275, coins_700: 700,
  coins_1700: 1700, coins_3800: 3800, coins_9200: 9200,
  coins_100_first: 100, coins_275_first: 275, coins_700_first: 700,
  coins_1700_first: 1700, coins_3800_first: 3800, coins_9200_first: 9200,
};
const SUBS = new Set(["ad_free_weekly", "ad_free_monthly"]);
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
function b64url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
function pemBytes(pem: string): Uint8Array {
  const raw = atob(pem.replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----/g, "").replace(/\s/g, ""));
  return Uint8Array.from(raw, c => c.charCodeAt(0));
}
let googleToken = "";
let googleTokenExpiry = 0;
async function getGoogleToken(): Promise<string> {
  if (googleToken && Date.now() < googleTokenExpiry - 60000) return googleToken;
  if (!ACCOUNT_JSON) throw new Error("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON secret is not configured");
  const account = JSON.parse(ACCOUNT_JSON);
  const now = Math.floor(Date.now() / 1000);
  const unsigned = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" })) + "." +
    b64url(JSON.stringify({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/androidpublisher",
      aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
    }));
  const key = await crypto.subtle.importKey("pkcs8", pemBytes(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: unsigned + "." + b64url(signature),
    }),
  });
  if (!response.ok) throw new Error("Google OAuth failed: " + response.status);
  const data = await response.json();
  googleToken = String(data.access_token ?? "");
  googleTokenExpiry = Date.now() + Number(data.expires_in ?? 3600) * 1000;
  if (!googleToken) throw new Error("Google OAuth returned no access token");
  return googleToken;
}
async function playApi(path: string, method = "GET", body?: unknown) {
  const response = await fetch(
    "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/" +
      encodeURIComponent(PACKAGE) + "/" + path,
    {
      method,
      headers: { Authorization: "Bearer " + await getGoogleToken(), "Content-Type": "application/json" },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    },
  );
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error("Google Play API failed: " + response.status);
  return data;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const authorization = req.headers.get("Authorization") ?? "";
    if (!authorization.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);
    const userClient = createClient(URL, ANON, { global: { headers: { Authorization: authorization } } });
    const { data: auth, error: authError } = await userClient.auth.getUser();
    if (authError || !auth.user) return json({ error: "Unauthorized" }, 401);
    const userId = auth.user.id;
    const admin = createClient(URL, SERVICE);
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "verify");
    let productId = String(body.productId ?? "");
    let purchaseToken = String(body.purchaseToken ?? "");

    if (action === "coin_offer_status") {
      const { data, error } = await admin.from("play_purchase_events")
        .select("purchase_token").eq("user_id", userId)
        .eq("purchase_type", "coin_pack").limit(1);
      if (error) throw error;
      return json({ success: true, eligible: !data || data.length === 0 });
    }

    if (action === "refresh_subscription") {
      const { data, error } = await admin.from("play_subscriptions")
        .select("product_id,purchase_token").eq("user_id", userId)
        .order("expires_at", { ascending: false }).limit(1).maybeSingle();
      if (error) throw error;
      if (!data) return json({ success: true, active: false });
      productId = String(data.product_id);
      purchaseToken = String(data.purchase_token);
    }

    if (!purchaseToken || purchaseToken.length < 20) return json({ error: "Invalid purchase token" }, 400);

    // Consuming is a separate authenticated step after the Flutter plugin has
    // acknowledged the transaction. The ledger prevents token reuse by another user.
    if (action === "consume") {
      if (!COINS[productId]) return json({ error: "Only coin products can be consumed" }, 400);
      const { data: ledger, error } = await admin.from("play_purchase_events")
        .select("user_id,product_id,purchase_type")
        .eq("purchase_token", purchaseToken).maybeSingle();
      if (error) throw error;
      if (!ledger || ledger.user_id !== userId || ledger.product_id !== productId ||
          ledger.purchase_type !== "coin_pack") return json({ error: "Purchase not owned by this account" }, 403);
      const purchase = await playApi("purchases/products/" + encodeURIComponent(productId) +
        "/tokens/" + encodeURIComponent(purchaseToken));
      if (Number(purchase.purchaseState) !== 0 || purchase.productId !== productId) {
        return json({ error: "Google Play purchase is not valid" }, 409);
      }
      if (Number(purchase.consumptionState) !== 1) {
        await playApi("purchases/products/" + encodeURIComponent(productId) +
          "/tokens/" + encodeURIComponent(purchaseToken) + ":consume", "POST", {});
      }
      return json({ success: true, consumed: true });
    }

    if (action !== "verify" && action !== "refresh_subscription") {
      return json({ error: "Unknown action" }, 400);
    }
    if (!COINS[productId] && !SUBS.has(productId)) return json({ error: "Unknown product" }, 400);

    if (COINS[productId]) {
      const purchase = await playApi("purchases/products/" + encodeURIComponent(productId) +
        "/tokens/" + encodeURIComponent(purchaseToken));
      if (Number(purchase.purchaseState) !== 0 || purchase.productId !== productId) {
        return json({ error: "Google Play has not confirmed this purchase" }, 409);
      }
      const { data, error } = await admin.rpc("record_verified_play_purchase", {
        p_user_id: userId, p_product_id: productId, p_purchase_token: purchaseToken,
        p_order_id: purchase.orderId ?? null, p_expires_at: null,
      });
      if (error) throw error;
      return json({ success: true, type: "coin_pack", coins: COINS[productId],
        duplicate: data?.duplicate === true });
    }

    const sub = await playApi("purchases/subscriptionsv2/tokens/" + encodeURIComponent(purchaseToken));
    const items = Array.isArray(sub.lineItems) ? sub.lineItems : [];
    const item = items.find((entry: Record<string, unknown>) => entry.productId === productId);
    const expiry = item?.expiryTime ? new Date(String(item.expiryTime)) : null;
    const validStates = new Set([
      "SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
      "SUBSCRIPTION_STATE_CANCELED",
    ]);
    if (!item || !expiry || expiry.getTime() <= Date.now() ||
        !validStates.has(String(sub.subscriptionState))) {
      if (action === "refresh_subscription") {
        const { error: revokeError } = await admin.rpc("revoke_play_subscription", {
          p_user_id: userId,
          p_purchase_token: purchaseToken,
        });
        if (revokeError) throw revokeError;
        return json({ success: true, active: false });
      }
      return json({ error: "Subscription is not currently active" }, 409);
    }
    const { data, error } = await admin.rpc("record_verified_play_purchase", {
      p_user_id: userId, p_product_id: productId, p_purchase_token: purchaseToken,
      p_order_id: sub.latestOrderId ?? null, p_expires_at: expiry.toISOString(),
    });
    if (error) throw error;
    return json({ success: true, type: "subscription", active: true,
      expiresAt: expiry.toISOString(), duplicate: data?.duplicate === true });
  } catch (error) {
    console.error("play-billing error", error);
    const message = error instanceof Error ? error.message : "Billing verification failed";
    if (message.includes("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")) {
      return json({ error: message, setupRequired: true }, 503);
    }
    return json({ error: "Purchase verification is temporarily unavailable" }, 503);
  }
});
