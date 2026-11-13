import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

initializeApp();
const db = getFirestore();

async function requireCurrentTermsVersion(): Promise<string> {
  const snapshot = await db.collection("appConfig").doc("legal").get();
  const version = String(snapshot.data()?.termsVersion ?? "").trim();
  if (!version) {
    throw new HttpsError(
      "failed-precondition",
      "The current Terms version is not configured by the administrator."
    );
  }
  return version;
}

/**
 * Creates the caller's public and private profile atomically.
 * Identity comes only from verified Firebase Auth context.
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

  const currentTermsVersion = await requireCurrentTermsVersion();
  if (termsVersion !== currentTermsVersion) {
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

/**
 * Returns only the authenticated caller's account state. Private email and
 * legal-consent metadata never leave this endpoint.
 */
export const getMyAccountState = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }

  const uid = request.auth.uid;
  const [publicSnap, privateSnap, currentTermsVersion] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("userPrivate").doc(uid).get(),
    requireCurrentTermsVersion(),
  ]);

  if (!publicSnap.exists || !privateSnap.exists) {
    throw new HttpsError("failed-precondition", "Account profile is not provisioned.");
  }

  const publicData = publicSnap.data()!;
  const privateData = privateSnap.data()!;
  return {
    uid,
    isBanned: publicData.isBanned === true,
    termsAccepted: privateData.termsAccepted === true &&
      privateData.termsVersion === currentTermsVersion &&
      privateData.termsAcceptedAt != null,
    currentTermsVersion,
  };
});

/**
 * Records explicit re-acceptance of the currently configured Terms version.
 */
export const acceptCurrentTerms = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  if (request.data?.accepted !== true) {
    throw new HttpsError("invalid-argument", "Explicit Terms acceptance is required.");
  }

  const uid = request.auth.uid;
  const currentTermsVersion = await requireCurrentTermsVersion();
  const privateRef = db.collection("userPrivate").doc(uid);

  await db.runTransaction(async (tx) => {
    const privateSnap = await tx.get(privateRef);
    if (!privateSnap.exists) {
      throw new HttpsError("failed-precondition", "Account profile is not provisioned.");
    }
    tx.update(privateRef, {
      termsAccepted: true,
      termsVersion: currentTermsVersion,
      termsAcceptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { ok: true, termsVersion: currentTermsVersion };
});
