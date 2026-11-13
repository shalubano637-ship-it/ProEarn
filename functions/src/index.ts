import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

initializeApp();
const db = getFirestore();

/**
 * Authenticated, idempotent profile provisioning.
 *
 * The UID and email are taken from the verified Firebase Auth context, never
 * from caller-supplied identity fields. The client must pass the exact Terms
 * version shown in the signup UI and an explicit acceptance flag.
 */
export const provisionMyProfile = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in before creating a profile.");
  }

  const uid = auth.uid;
  const username = String(request.data?.username ?? "").trim();
  const termsVersion = String(request.data?.termsVersion ?? "").trim();
  const acceptedTerms = request.data?.acceptedTerms === true;
  const referralCode = String(request.data?.referralCode ?? "")
    .trim()
    .toUpperCase();

  if (username.length < 3 || username.length > 24) {
    throw new HttpsError("invalid-argument", "Username must be 3 to 24 characters.");
  }
  if (!acceptedTerms || termsVersion.length < 1 || termsVersion.length > 40) {
    throw new HttpsError("failed-precondition", "Accept the current Terms of Service.");
  }
  if (referralCode && !/^[A-Z0-9_-]{3,32}$/.test(referralCode)) {
    throw new HttpsError("invalid-argument", "Referral code format is invalid.");
  }

  const termsRef = db.collection("appConfig").doc("legal");
  const termsSnapshot = await termsRef.get();
  const currentTermsVersion = String(termsSnapshot.data()?.termsVersion ?? "").trim();
  if (!currentTermsVersion || termsVersion !== currentTermsVersion) {
    throw new HttpsError("failed-precondition", "Terms have changed. Review and accept the current version.");
  }

  const publicRef = db.collection("users").doc(uid);
  const privateRef = db.collection("userPrivate").doc(uid);

  await db.runTransaction(async (tx) => {
    const [publicSnap, privateSnap] = await Promise.all([
      tx.get(publicRef),
      tx.get(privateRef),
    ]);

    if (publicSnap.exists || privateSnap.exists) {
      if (!publicSnap.exists || !privateSnap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Account profile is incomplete; support review is required."
        );
      }
      return;
    }

    tx.create(publicRef, {
      uid,
      userName: username,
      bio: "No Bio Yet",
      link: "No Link",
      profileUrl: "",
      isBanned: false,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    tx.create(privateRef, {
      uid,
      email: auth.token.email ?? null,
      termsAccepted: true,
      termsVersion,
      termsAcceptedAt: FieldValue.serverTimestamp(),
      pendingReferralCode: referralCode || null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { ok: true, uid };
});
