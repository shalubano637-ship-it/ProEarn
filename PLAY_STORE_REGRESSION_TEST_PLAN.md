# ProSN release regression checklist

Run this on a physical Android device using a fresh test account and a second
account for chat/report/block scenarios. Do not use a personal production
account for destructive deletion tests.

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
- [ ] Verify legacy ImgBB content separately; old third-party media may need provider-side cleanup.

## Social and messaging

- [ ] Create a post, like, unlike, comment, reply, share, and delete owned content.
- [ ] Send text and image messages between two test accounts.
- [ ] Verify chat opens at the latest message and scrolls correctly.
- [ ] Test message requests, blocked users, and notification preferences.
- [ ] Verify push notifications on Android 13+ after permission is granted.

## Rewards and ads

- [ ] Start, pause, resume, and expire a chest timer.
- [ ] Confirm chest-ready notification is not duplicated.
- [ ] Test coin balance, gift inventory, gift sending, and leaderboard updates.
- [ ] Test rewarded ads only grant in-app virtual rewards, never direct cash or monetary items.
- [ ] Confirm daily ad reward caps are enforced server-side.


## Google Play Console and Android policy checks

- [ ] Confirm the release AAB targets Android 16 / API 36. Do not infer this from compileSdk; inspect the built artifact or Play Console's App Bundle Explorer.
- [ ] Inspect the merged release manifest. Legacy READ_EXTERNAL_STORAGE is limited to API 32 and WRITE_EXTERNAL_STORAGE to API 28; confirm no broad all-files or unnecessary photo/video permissions are added by dependencies.
- [ ] Confirm the Play listing package name is exactly `com.example.proearn` (or update the app configuration and Firebase registration together if the actual Play package differs).
- [ ] In Play Console → App content → App access, provide a working reviewer account and exact sign-in instructions. Keep the test account active, seeded with usable content, and accessible for the full review. If email/OTP verification is required, explain the reviewer path and provide the required access details through Play Console's secure fields.
- [ ] Complete the Data safety form from the actual production SDK configuration and data flows. Review account identifiers, email, user content/messages, photos, device/diagnostic data, push tokens, advertising identifiers, and data shared with Supabase, Cloudflare, Firebase, AdMob, Sentry, and any remaining ImgBB flow.
- [ ] Set Target Audience and Content Rating truthfully for the actual intended audience and app features. Do not select an age group merely to bypass child-safety requirements.
- [ ] Verify the public Privacy Policy, Account Deletion, Community Guidelines, and Child Safety Standards pages load in a signed-out/incognito browser and contain the current support contact.
- [ ] Confirm the public account-deletion flow works end-to-end with a disposable account, including email ownership verification, server-side deletion, and honest success/failure messages.
- [ ] Confirm the app's in-app report/block controls and the published UGC/child-safety rules match the production moderation and support process.
- [ ] Do not submit until the physical-device regression checklist above is completed and the release AAB has passed CI.

## Release validation

- [ ] Confirm applicationId matches the Play Console app and google-services.json.
- [ ] Confirm versionCode is greater than the highest uploaded Play version code.
- [ ] Build a signed release AAB with the private upload keystore.
- [ ] Verify the public Privacy Policy and account-deletion URLs open without login.
- [ ] Complete Play Console Data Safety, Ads, Content Rating, Target Audience, and App Access declarations.
