# App Signing — READ BEFORE BUILDING A RELEASE

Android only installs an update if the new APK is signed with the **exact same key**
as the version already on the phone. In July 2026 the app was accidentally signed with
a debug key and **every user had to uninstall and reinstall the app**. Follow these
rules so that never happens again.

## The one permanent key

- Keystore: `android/app/alraqi-release.jks` (alias `alraqi`)
- Passwords: in `android/key.properties`
- Both files are **gitignored on purpose** (they are secrets). A fresh `git clone`
  does NOT contain them — release builds will fail with a clear error until you
  restore them from backup.

## Backup locations (keep at least one off this computer!)

1. `C:\Users\ragab\Documents\alraqi-keystore-backup\` (local copy)
2. **TODO: copy both files to a password manager / cloud drive / USB stick.**
   If this computer dies and there is no off-machine copy, the app can never be
   updated in place again.

## Rules

1. **Never** delete, regenerate, or replace `alraqi-release.jks`.
2. **Never** change the `signingConfig` in `app/build.gradle.kts` back to `debug`.
3. Building on a new machine? Copy `alraqi-release.jks` into `android/app/` and
   `key.properties` into `android/` from the backup first.
4. Before each release, **increase the version** in `pubspec.yaml`
   (e.g. `1.0.3+4` → `1.0.4+5`). The number after `+` (versionCode) must always
   go up, or phones will refuse the update.
5. Only distribute APKs built with `flutter build apk --release` from a machine
   that has the real keystore. Verify the signature if unsure:

   ```
   apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk
   ```

   The certificate must be `CN=Alraqi, O=Alraqi, C=SA` with SHA-256
   `77dd1fb622bd74f5347693f4dd3ce6afef3d4e2b548d925a4ef3b49126f06b08`.
