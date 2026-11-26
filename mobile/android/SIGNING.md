# Android release signing (local builds)

Short version: **back up the debug keystore before it is lost** (Option B).
If you want a real release key, follow Option A, which keeps the update path
alive through an `apksigner` rotation lineage.

## What v2.0.0 and v2.1.0 are signed with

| | |
|---|---|
| Certificate | `CN=Android Debug` |
| SHA-256 | `804591F4D096CF6286BC18816BD2D524CA4EA10254E78756D1647039F9A16DE5` |
| Keystore | `%USERPROFILE%\.android\debug.keystore` (outside the repository) |
| Store / key password | `android` (alias `androiddebugkey`) |

Android only installs an update when the new APK is signed with the same key,
so this file is the identity of the app. The repository does not contain it and
`mobile/android/.gitignore` keeps it out.

## Option B - keep the debug key (recommended right now)

No configuration change: without `key.properties`, the release build keeps using
the debug signing config, which is what every build so far did. Only do this:

```powershell
cd mobile\android
powershell -ExecutionPolicy Bypass -File signing_setup.ps1 -Action backup
```

It copies the keystore plus a small `README.txt` (file hash, certificate hash,
passwords) to `%USERPROFILE%\ecg-signing-backup-<date>`. Move that folder to a
password manager or an encrypted drive. If it is lost, every installed copy has
to be uninstalled before it can be replaced.

Same result by hand:

```powershell
Copy-Item "$env:USERPROFILE\.android\debug.keystore" "$env:USERPROFILE\ecg-debug.keystore.bak"
```

## Option A - a real release key, with rotation from the debug key

`apksigner` can prove that the new key replaces the old one, so devices that
have the debug-signed app accept the update. This was verified locally with
build-tools 35.0.0: the signed APK reports the release signer for API 33+ and
the debug signer for API 24-32, and `apksigner verify` passes for both.

1. Create `release.jks` and `lineage.bin` (asks for the new password; the debug
   keystore password defaults to `android`):

```powershell
cd mobile\android
powershell -ExecutionPolicy Bypass -File signing_setup.ps1 -Action rotate
```

2. Create `mobile/android/key.properties` (git-ignored) so Gradle signs with the
   new key:

```properties
storeFile=../release.jks
keyAlias=release
storePassword=<the password you typed>
keyPassword=<the same password>
```

3. Build and re-sign so the lineage travels with the APK:

```powershell
flutter build apk --release --split-per-abi

# once per ABI: add the old signer and the lineage
apksigner sign `
  --ks android\release.jks --ks-pass pass:<new password> --ks-key-alias release `
  --next-signer --ks "$env:USERPROFILE\.android\debug.keystore" `
  --ks-pass pass:android --ks-key-alias androiddebugkey `
  --lineage android\lineage.bin `
  --in build\app\outputs\flutter-apk\app-arm64-v8a-release.apk `
  --out build\app\outputs\flutter-apk\app-arm64-v8a-v2.1.0.apk
```

4. Check that both signers are present:

```powershell
apksigner verify --min-sdk-version 24 --print-certs <the signed apk>
```

The output must contain two signers: `CN=ECG Beat Classifier` for API 33+ and
`CN=Android Debug` for API 24-32. That combination is what keeps already
installed copies updatable.

5. Back up `release.jks`, `lineage.bin` and the passwords together. Without the
   lineage file the rotation proof is gone and API 33+ devices would refuse the
   update.

`minSdkVersion` of the app is 24, so APK Signature Scheme v1 is never needed;
`apksigner` handles v2/v3 on its own.

## Never commit

`key.properties`, `*.jks`, `*.keystore` and `lineage.bin` are ignored by
`mobile/android/.gitignore`. Treat them as secrets and back them up.
