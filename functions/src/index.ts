import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { beforeUserCreated } from "firebase-functions/v2/identity";

initializeApp();
const db = getFirestore();

/**
 * Blocks malformed signup metadata before Firebase creates the account.
 * Referral attribution is recorded as pending input only; a separate trusted
 * referral workflow must validate and apply rewards.
 */
export const validateNewAccount = beforeUserCreated(async (event) => {
  const data = event.data;
  if (!data) {
    throw new Error("Missing account data");
  }

  const username = String(data.displayName ?? "").trim();
  if (username.length < 3 || username.length > 24) {
    throw new Error("Username must be between 3 and 24 characters.");
  }

  const termsAccepted = data.customClaims?.termsAccepted === true;
  const termsVersion = String(data.customClaims?.termsVersion ?? "").trim();
  if (!termsAccepted || !termsVersion) {
    throw new Error("Current Terms of Service must be accepted.");
  }

  return {
    displayName: username,
    customClaims: {
      termsAccepted: true,
      termsVersion,
    },
  };
});

/**
 * Creates the minimal public profile and private account record using the
 * Admin SDK. Clients cannot set moderation fields or mint wallet balances.
 * No referral rewards or coins are granted by this trigger.
 */
export const provisionUserProfile = async (event: { data: { uid: string; email?: string; displayName?: string } }) => {
  const user = event.data;
  const uid = user.uid;
  if (!uid) {
    logger.error("Auth create event did not include a UID");
    return;
  }

  const publicRef = db.collection("users").doc(uid);
  const privateRef = db.collection("userPrivate").doc(uid);
  const authUser = user;

  await db.runTransaction(async (tx) => {
    const [publicSnap, privateSnap] = await Promise.all([
      tx.get(publicRef),
      tx.get(privateRef),
    ]);

    if (!publicSnap.exists) {
      tx.create(publicRef, {
        uid,
        userName: String(authUser.displayName ?? "").trim(),
        bio: "No Bio Yet",
        link: "No Link",
        profileUrl: "",
        isBanned: false,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    if (!privateSnap.exists) {
      tx.create(privateRef, {
        uid,
        email: authUser.email ?? null,
        termsAccepted: true,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
};
