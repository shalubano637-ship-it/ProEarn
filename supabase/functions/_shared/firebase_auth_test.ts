import { hasSupabaseAuthenticatedRole, isFirebaseUuidUid } from "./firebase_auth_claims.ts";

Deno.test("accepts UUID-shaped Firebase subjects", () => {
  if (!isFirebaseUuidUid("e4264a28-2fc3-18bf-8f75-78ee71dc889f")) {
    throw new Error("Expected valid UUID to pass");
  }
});

Deno.test("rejects Firebase default non-UUID subjects", () => {
  if (isFirebaseUuidUid("firebase-user-123")) throw new Error("Expected non-UUID UID to fail");
  if (isFirebaseUuidUid(null)) throw new Error("Expected null UID to fail");
});

Deno.test("requires UUID subject and authenticated role claim", () => {
  const uid = "e4264a28-2fc3-18bf-8f75-78ee71dc889f";
  if (!hasSupabaseAuthenticatedRole({ uid, role: "authenticated" })) throw new Error("Expected valid claims");
  if (hasSupabaseAuthenticatedRole({ uid, role: "anon" })) throw new Error("Expected anon role to fail");
  if (hasSupabaseAuthenticatedRole({ uid: "not-a-uuid", role: "authenticated" })) throw new Error("Expected non-UUID subject to fail");
});
