# ProSN Android release signing

The Android package identifier is currently `com.prosn.app` and matches
`android/app/google-services.json`. Keep `namespace` and `applicationId`
aligned. Do not change the application ID after the first Play Store upload:
Google Play treats a different application ID as a different app.

## Confirm the Play package and version

Before the first upload, confirm the intended package ID in Play Console. The current
ID is `com.prosn.app`, matching `google-services.json`; keep it unchanged
if that is already the app's Play package. If this app has never been uploaded,
choose its final unique package ID before the first upload and regenerate the
matching Firebase Android app configuration. Also set the `pubspec.yaml` build
number to a value greater than the highest version code already uploaded to Play.

## Create the upload keystore

Run this on a trusted machine and store the keystore and passwords securely:

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Place the keystore at `android/upload-keystore.jks` and create
`android/key.properties` using `android/key.properties.example`. Never commit
either the keystore or the real `key.properties` file.

## GitHub Actions release bundle

To enable the signed App Bundle workflow, add the following repository Actions
secrets:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded contents of `upload-keystore.jks`
- `ANDROID_KEYSTORE_PASSWORD`: keystore password
- `ANDROID_KEY_ALIAS`: `upload` (or the alias you chose)
- `ANDROID_KEY_PASSWORD`: key password

Then add the repository Actions variable
`ANDROID_RELEASE_SIGNING_CONFIGURED=true`. The workflow will create the
keystore file at build time and run `flutter build appbundle --release`.

Release builds intentionally fail if the private keystore is missing. The
ordinary CI job still runs analysis/tests and produces a debug APK for smoke
testing; that debug APK is not a Play Store upload artifact.
