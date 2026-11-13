import { readFile } from "node:fs/promises";
import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import {
  assertFails,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";

const projectId = "demo-prosn-firestore-rules";
let env;

before(async () => {
  const rules = await readFile(new URL("../../firestore.rules", import.meta.url), "utf8");
  env = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });
});

after(async () => {
  await env?.cleanup();
});

test("unauthenticated clients cannot read or write user profiles", async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, "users/user-a")));
  await assertFails(setDoc(doc(db, "users/user-a"), { userName: "attacker" }));
});

test("authenticated clients cannot read or write public or private user documents", async () => {
  const db = env.authenticatedContext("user-a").firestore();
  await assertFails(getDoc(doc(db, "users/user-a")));
  await assertFails(setDoc(doc(db, "users/user-a"), { isBanned: false }));
  await assertFails(getDoc(doc(db, "userPrivate/user-a")));
  await assertFails(setDoc(doc(db, "userPrivate/user-a"), {
    termsAccepted: true,
    email: "forged@example.com",
  }));
});

test("clients cannot create or change moderation state for another user", async () => {
  const db = env.authenticatedContext("user-a").firestore();
  await assertFails(setDoc(doc(db, "users/user-b"), {
    uid: "user-b",
    isBanned: false,
    role: "admin",
  }));
});

test("admin SDK can seed records while client rules remain closed", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/user-a"), {
      uid: "user-a",
      isBanned: false,
    });
  });

  const clientDb = env.authenticatedContext("user-a").firestore();
  await assertFails(getDoc(doc(clientDb, "users/user-a")));
});
