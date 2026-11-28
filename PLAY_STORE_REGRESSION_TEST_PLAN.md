# ProSN release regression checklist

Run this on a physical Android device using a fresh test account and a second
account for chat/report/block scenarios. Do not use a personal production
account for destructive deletion tests.

## Automated CI checks (verified)

The following checks passed in GitHub Actions run
[46128711255](https://github.com/shalubano637-ship-it/ProEarn/actions/runs/46128711255)
on 2026-11-28 for commit
`e67ad372b0baa77d2ab6ed2d019fccbea19e1e3c` on `main`.

These are CI/automated checks only. They do not count as physical-device,
live-account, payment-provider, or end-to-end tests.

- [x] Flutter static analysis completed successfully (0 errors; 29 warnings and 212 info notices were reported).
- [x] Flutter unit tests passed: 14/14 in `test/chest_timer_service_test.dart`.
- [x] Deno type checks passed for the Firebase auth helpers and the configured provisioning, Google bridge, account deletion, R2 upload, notifications, Play Billing, moderation, and voice-message functions.
- [x] Firebase Auth helper Deno tests passed (`supabase/functions/_shared/firebase_auth_test.ts`).
- [x] Persistent upload keystore was restored; the actual debug APK signer was verified against that keystore and the Firebase SHA-1 registration.
- [x] Release signing certificate and Firebase package/Web OAuth configuration checks passed.
- [x] Signed release APK and signed Android App Bundle (AAB) were built and uploaded as CI artifacts.

## Requested live test status (2026-11-28)

These results are from a read-only live Supabase inspection plus one reversible
block/unblock database smoke test. A deployed function, source-code inspection,
or historical row count is not an end-to-end pass. The nine top-level checks
remain open until tested on a real Android device with dedicated test accounts.

- [ ] **Real device installation** — not performed. The CI APK artifact exists,
  but no Android phone/emulator is connected to install or launch it.
- [ ] **Email and Google login** — Firebase email/password and Google bridge
  paths were inspected; the provisioning and Google bridge functions are
  deployed ACTIVE. No live email verification, Google account login, logout,
  or relogin was executed.
- [ ] **Chat and messaging** — not E2E tested. Live database counts: 0
  conversations, 0 message requests, 0 direct messages, and 0 room messages.
- [ ] **Block/unblock end-to-end** — app UI and real-device interaction remain
  untested.
  - [x] Live database smoke test passed for the deployed
    `block_user_and_hide_post`, `is_blocked_by_user`, and `unblock_user`
    functions. It applied a block between two existing profiles, verified the
    blocked-state check from the other profile, unblocked, and verified the
    state cleared. The test ended with 0 users having any blocked IDs; no block
    was left in place. This was a SQL-side smoke test with simulated JWT
    claims, not a Flutter/API-device test.
- [ ] **Reporting and moderation** — the full report-to-admin-to-takedown
  flow has not yet been exercised end-to-end on a device with two test accounts.
  - [x] Post, comment, direct-message, user, and Room Chat report UI paths are
    present in the Flutter source.
  - [x] Room Chat report snapshots now preserve message text, image URL, and
    whether a voice attachment was present; the admin dashboard labels and
    previews `room_message` reports and offers a dedicated removal action.
  - [x] The live `get_room_messages` RPC now returns a voice-attachment flag,
    duration, and listen counters without exposing the private R2 voice key.
    The migration was applied; SQL grants were verified as authenticated-only
    (anon cannot execute the RPC).
  - [x] Live `admin-moderate-report` is ACTIVE (v10). The Room Chat action
    verifies the report source and sender match, removes the `room_messages`
    row, deletes its R2 chat image/voice object, marks the report actioned,
    and notifies the reporter. The Edge Function verifies Firebase identity
    and admin allow-list membership itself; gateway `verify_jwt` is disabled
    to allow the Firebase token to reach that verifier.
  - [ ] Device E2E remains open: submit a Room Chat text/image/voice report
    from a non-admin test account, verify it appears with the correct sender
    and preview in Admin → Reports, remove it as admin, then verify the row
    and R2 media are gone and the reporter receives the action notification.
  - [x] Existing database has 6 earlier reports, all `dismissed`, and 0
    pending reports. This is historical state, not proof of the new flow.
- [ ] **Billing and subscriptions** — not tested through Google Play.
  - [x] Live `play-billing` function is ACTIVE (v10); client product IDs and
    server verification/ledger code were inspected.
  - [x] Live ledger currently has 0 purchase events and 0 subscription rows.
  - [ ] License-tester purchase, coin credit, weekly/monthly renewal, cancel,
    refund, restore, duplicate callback, and entitlement checks remain open.
  - [ ] Google Play RTDN is not configured, so off-app cancellation/refund
    updates are not yet verified.
- [ ] **Ads and rewards** — not E2E tested.
  - [x] Confirmed `lib/ad_unit_ids.dart` and the Android manifest still use
    Google's sample/test AdMob IDs. Production ad delivery cannot be validated
    with these IDs.
  - [ ] Rewarded-ad completion, server-side reward grant, duplicate prevention,
    daily caps, and chest claim remain open.
- [ ] **Account deletion E2E** — not independently re-run or verified in this
  session.
  - [x] Live `delete-account-request` (v22) and `delete-account` (v26)
    functions are ACTIVE; source enforces Firebase token and verified-email
    checks.
  - [x] The deletion-request table has 4 records, all with status
    `completed`. This is backend record evidence only; Firebase Auth user
    removal, R2 cleanup, app auto-logout, and rejected post-deletion login
    were not independently checked.
- [ ] **Push notifications** — device delivery remains untested.
  - [x] Two user records currently have an FCM token and push enabled.
  - [x] Live `notify` function is ACTIVE (v60) and uses Firebase Cloud
    Messaging HTTP v1 in its send path.
  - [ ] Android permission prompt, foreground/background delivery, tap
    navigation, and delivery on a real device remain open.

No payment, account deletion, report takedown, post upload, or message was
triggered by this audit. The only stateful smoke test was block/unblock, and
the test removed its temporary block before completing.

### Chest timer unit-test coverage

- [x] Unit-tested chest timer schedule, start, countdown, pause/persist, foreground resume, expiry, already-unlocked state, signed-out state, repository error handling, and disposal (14/14 tests).
- [ ] End-to-end chest reward flow: ad verification, server-side reward/claim persistence, actual claim, and push-notification delivery.

## Build and install

- [ ] Install the CI debug APK on a clean device.
- [ ] Launch, force-close, relaunch, and verify there is no crash or stuck splash.
- [ ] Verify the app does not request package-install permission or open an external APK installer.
- [ ] Verify app updates are handled by Google Play, not by an in-app APK download.

## Authentication and account

- [ ] Sign up with a new email and complete email verification.
- [ ] Sign in, sign out, and sign back in.
- [ ] Test invalid password and password-reset flows without revealing whether an email exists.
- [ ] Open Settings → Security and verify the in-app account deletion confirmation flow.
- [ ] On a separate test account, open the public account-deletion page, request an OTP, verify the code, and confirm deletion.
- [ ] After deletion, verify the Auth user, profile, posts, comments, messages, notifications, follows, likes, rooms, and R2 media are gone or anonymized as documented.
- [ ] Verify the same user cannot sign in after successful deletion.
- [ ] Verify a failed R2 cleanup leaves the account available for retry and does not report success.

## User-generated content and moderation

- [ ] Upload a safe image as a post, profile photo, chat image, comment image, and room image.
- [ ] Confirm each upload passes the server-side moderation path before storage.
- [ ] Test prohibited/unsafe images in each category using approved test material; confirm the upload is rejected.
- [ ] Confirm moderation service errors fail closed and do not store the image.
- [ ] Report a post, comment, chat message, and account.
- [ ] Block a user and verify blocked interactions are prevented.
- [ ] Confirm admin review can inspect report snapshots and remove reported content.
- [ ] Verify historical externally hosted image URLs still load where expected; confirm legacy external objects are handled separately from managed R2 cleanup.

## Social and messaging

- [ ] Create a post, like, unlike, comment, reply, share, and delete owned content.
- [ ] Send text and image messages between two test accounts.
- [ ] Verify chat opens at the latest message and scrolls correctly.
- [ ] Test message requests, blocked users, and notification preferences.
- [ ] Verify push notifications on Android 13+ after permission is granted.

## Rewards and ads

- [ ] Confirm chest-ready notification is not duplicated.
- [ ] Test coin balance, gift inventory, gift sending, and leaderboard updates.
- [ ] Test rewarded ads only grant in-app virtual rewards, never direct cash or monetary items.
- [ ] Confirm daily ad reward caps are enforced server-side.

## Google Play Console and Android policy checks

- [ ] Confirm the release AAB targets Android 16 / API 36. Do not infer this from compileSdk; inspect the built artifact or Play Console's App Bundle Explorer.
- [ ] Inspect the merged release manifest. Legacy READ_EXTERNAL_STORAGE is limited to API 32 and WRITE_EXTERNAL_STORAGE to API 28; confirm no broad all-files or unnecessary photo/video permissions are added by dependencies.
- [ ] Confirm the Play listing package name is exactly `com.prosn.app` and matches the app configuration and Firebase registration.
- [ ] In Play Console → App content → App access, provide a working reviewer account and exact sign-in instructions. Keep the test account active, seeded with usable content, and accessible for the full review. If email/OTP verification is required, explain the reviewer path and provide the required access details through Play Console's secure fields.
- [ ] Complete the Data safety form from the actual production SDK configuration and data flows. Review account identifiers, email, user content/messages, photos, device/diagnostic data, push tokens, advertising identifiers, and data shared with Supabase, Cloudflare, Firebase, AdMob, and Sentry, including the current Cloudflare R2 upload and moderation flow.
- [ ] Set Target Audience and Content Rating truthfully for the actual intended audience and app features. Do not select an age group merely to bypass child-safety requirements.
- [ ] Verify the public Privacy Policy, Account Deletion, Community Guidelines, and Child Safety Standards pages load in a signed-out/incognito browser and contain the current support contact.
- [ ] Confirm the public account-deletion flow works end-to-end with a disposable account, including email ownership verification, server-side deletion, and honest success/failure messages.
- [ ] Confirm the app's in-app report/block controls and the published UGC/child-safety rules match the production moderation and support process.
- [ ] Do not submit until the physical-device regression checklist above is completed and the release AAB has passed CI.

## Release validation

- [x] CI verified `applicationId` and the Firebase Android client both use `com.prosn.app`.
- [ ] Confirm the Play Console listing package matches `com.prosn.app`.
- [ ] Confirm versionCode is greater than the highest uploaded Play version code.
- [x] Build a signed release AAB with the persistent private upload keystore (verified in the CI run linked above).
- [ ] Verify the public Privacy Policy and account-deletion URLs open without login.
- [ ] Complete Play Console Data Safety, Ads, Content Rating, Target Audience, and App Access declarations.

## Historical manual retest confirmation (user-confirmed 2026-11-28)

The user confirmed that the previously reported non-billing issues were fixed
and manually retested successfully. Record this as historical user-reported
manual test evidence; it is not independently reproduced by the 2026-11-28
read-only/backend audit and does not replace a fresh-build release regression.

- [x] APK installation/launch and the previously failing logout/relogin flow
  were retested and reported passing.
- [x] Email authentication and Google Sign-In, including the previously
  reported Google login error, were retested and reported passing.
- [x] Chat/message sending, previously reported as stopped, was retested and
  reported passing.
- [x] Block/unblock UI and related previously reported UI issues were retested
  and reported passing.
- [x] Chest reward/timer behavior, previously reported as failing/resetting,
  was retested and reported passing.
- [x] Account-deletion flow issues previously reported by the user were
  retested and reported passing. This confirmation does not independently
  establish every backend cleanup sub-step listed above.
- [ ] Coins purchase and coin-credit flow — explicitly excluded by the user;
  still not passing/confirmed.
- [ ] Weekly Pass purchase/entitlement/ad behavior — explicitly excluded by
  the user; still not passing/confirmed.

The user reports all other previously tested flows as PASS after fixes.
Keep the two billing items above open. Do not mark billing complete based on
this confirmation. Detailed items that were never previously tested (for
example, report-to-takedown, FCM delivery, refunds/renewals, or production
AdMob delivery) remain subject to their own test evidence.
