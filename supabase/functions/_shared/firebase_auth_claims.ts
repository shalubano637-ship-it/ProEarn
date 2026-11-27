const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/**
 * Pure Firebase UID validation shared by Edge Functions and unit tests.
 *
 * Keep this module free of Firebase Admin / Node compatibility imports so
 * Deno can test the JWT claim rules without granting process-wide env access.
 */
export function isFirebaseUuidUid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

/** Confirms the Firebase JWT has the role and UUID subject required by Supabase RLS. */
export function hasSupabaseAuthenticatedRole(
  claims: { uid?: unknown; role?: unknown },
): boolean {
  return claims.role === "authenticated" && isFirebaseUuidUid(claims.uid);
}
