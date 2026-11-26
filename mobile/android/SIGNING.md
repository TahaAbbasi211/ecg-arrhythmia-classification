# Android release signing

Release builds fail closed unless `mobile/android/key.properties` is present.
Debug builds and `flutter test` continue to work without `key.properties`.

If you intentionally need a local debug-signed release build without `key.properties`,
pass `-PallowDebugRelease=true` explicitly to Gradle (`flutter build apk --release --android-project-arg allowDebugRelease=true`
or `./gradlew assembleRelease -PallowDebugRelease=true`).

---

## Option A — Permanent dedicated `release.jks` (recommended)

Use a dedicated, permanent release keystore (`release.jks`) for all future builds and
Play Store / public releases. Do **not** use the shared `CN=Android Debug` key
(password `android`) for production distribution.

> **Upgrade note for v2.0.0 / v2.1.0 users:** Earlier sideloaded builds (`v2.0.0` and `v2.1.0`)
> were signed with `CN=Android Debug` (`SHA-256: 804591F4D096CF6286BC18816BD2D524CA4EA10254E78756D1647039F9A16DE5`).
> For a clean cutover to a real release key (required for Play Store and recommended going forward),
> users with an earlier debug-signed copy simply uninstall it once before installing the new release.

1. Generate `mobile/android/release.jks`:

```powershell
cd mobile\android
powershell -ExecutionPolicy Bypass -File signing_setup.ps1 -Action create
```

2. Create `mobile/android/key.properties` (git-ignored) pointing to `release.jks`:

```properties
storeFile=../release.jks
keyAlias=release
storePassword=<the password you typed>
keyPassword=<the same password>
```

3. Build the release APKs:

```powershell
cd mobile
flutter build apk --release --split-per-abi
```

4. Back up `release.jks`, `key.properties`, and the passwords safely outside the repository
   (for example in a password manager or encrypted drive).

---

## Option B — Key rotation from the legacy debug key (`lineage.bin`, sideloaded updates only)

If you must preserve in-place sideloaded upgrades over existing `v2.0.0` / `v2.1.0`
debug-signed installations, `apksigner` can link the old debug key to your new `release.jks`
using a rotation lineage (API 24–32 verifies the old debug signer; API 33+ verifies the new release signer).

1. Create `release.jks` and `lineage.bin`:

```powershell
cd mobile\android
powershell -ExecutionPolicy Bypass -File signing_setup.ps1 -Action rotate
```

2. Create `mobile/android/key.properties` (git-ignored) as shown in Option A, then build:

```powershell
cd mobile
flutter build apk --release --split-per-abi
```

3. Re-sign each APK with the **old signer first** and the **new signer after `--next-signer`**, passing `--lineage`:

```powershell
apksigner sign `
  --ks "$env:USERPROFILE\.android\debug.keystore" --ks-pass pass:android --ks-key-alias androiddebugkey `
  --next-signer --ks android\release.jks --ks-pass pass:<new password> --ks-key-alias release `
  --lineage android\lineage.bin `
  --in build\app\outputs\flutter-apk\app-arm64-v8a-release.apk `
  --out build\app\outputs\flutter-apk\app-arm64-v8a-v2.1.1.apk
```

4. Verify both signers are present:

```powershell
apksigner verify --min-sdk-version 24 --print-certs build\app\outputs\flutter-apk\app-arm64-v8a-v2.1.1.apk
```

5. Back up `release.jks`, `lineage.bin`, and passwords together.

`minSdkVersion` is 24, so APK Signature Scheme v1 is not needed; `apksigner` handles v2/v3.

---

## Legacy fallback — backing up the old debug keystore (not recommended for releases)

For local archival of the legacy `v2.0.0` / `v2.1.0` debug key only (never recommended for
production or public releases):

```powershell
cd mobile\android
powershell -ExecutionPolicy Bypass -File signing_setup.ps1 -Action backup
```

## Never commit

`key.properties`, `*.jks`, `*.keystore`, and `lineage.bin` are ignored by
`mobile/android/.gitignore`. Never commit them to version control.
