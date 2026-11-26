import { cert, getApps, initializeApp } from "npm:firebase-admin@13.2.0/app";
import { getAuth } from "npm:firebase-admin@13.2.0/auth";

const EXPECTED_FIREBASE_PROJECT_ID = "proearn-6acdd";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class FirebaseRequestAuthError extends Error {
  constructor(message = "Unauthorized") {
    super(message);
    this.name = "FirebaseRequestAuthError";
  }
}

export type FirebaseRequestPrincipal = {
  uid: string;
  email: string | null;
  emailVerified: boolean;
};

function firebaseAdminAuth() {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON is not configured");
  const serviceAccount = JSON.parse(raw);
  if (serviceAccount.project_id !== EXPECTED_FIREBASE_PROJECT_ID) {
    throw new Error("Firebase service account project does not match ProSN");
  }
  const app = getApps()[0] ?? initializeApp({
    credential: cert(serviceAccount),
    projectId: EXPECTED_FIREBASE_PROJECT_ID,
  });
  return getAuth(app);
}

export function isFirebaseUuidUid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

export function hasSupabaseAuthenticatedRole(
  claims: { uid?: unknown; role?: unknown },
): boolean {
  return claims.role === "authenticated" && isFirebaseUuidUid(claims.uid);
}

export async function verifyFirebaseRequest(
  request: Request,
  options: { requireEmailVerified?: boolean } = {},
): Promise<FirebaseRequestPrincipal> {
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new FirebaseRequestAuthError();
  const token = authorization.slice("Bearer ".length).trim();
  if (!token || token.length > 12000) throw new FirebaseRequestAuthError();

  const auth = firebaseAdminAuth();
  let decoded;
  try {
    decoded = await auth.verifyIdToken(token, true);
  } catch {
    throw new FirebaseRequestAuthError();
  }
  if (!hasSupabaseAuthenticatedRole(decoded)) throw new FirebaseRequestAuthError();

  let user;
  try {
    user = await auth.getUser(decoded.uid);
  } catch {
    throw new FirebaseRequestAuthError();
  }
  if (user.disabled) throw new FirebaseRequestAuthError();
  if (options.requireEmailVerified === true && user.emailVerified !== true) {
    throw new FirebaseRequestAuthError("Email verification required");
  }
  return {
    uid: user.uid,
    email: user.email?.trim().toLowerCase() ?? decoded.email?.trim().toLowerCase() ?? null,
    emailVerified: user.emailVerified === true,
  };
}
