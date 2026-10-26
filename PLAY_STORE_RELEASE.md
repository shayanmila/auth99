# Easy Authenticator — Play Store release

## Signed Android App Bundle

Run **Actions → Play Store Signed AAB → Run workflow**. Supply the Play Store version name and a unique, increasing version code. Download the AAB from the completed workflow's **Artifacts** section.

The workflow requires these four GitHub Actions repository secrets:

- `ANDROID_KEYSTORE_BASE64` — base64-encoded upload keystore (.jks)
- `ANDROID_KEYSTORE_PASSWORD` — keystore password
- `ANDROID_KEY_ALIAS` — upload key alias
- `ANDROID_KEY_PASSWORD` — upload key password

Keep the original upload keystore backed up securely. Never commit the keystore or passwords. The AAB workflow fails early if any signing secret is missing. It does **not** use a debug key or generate a new signing identity on every run.

Proposed Android package ID: `com.masoomdev.easyauthenticator`. Confirm this identifier is the one you want **before first Play Console upload**. Google Play package IDs cannot be changed for an existing app.

The normal `build.yml` workflow still produces testing APK and Windows ZIP on pushes. The Play Store AAB workflow runs **only manually**, to avoid unnecessary release builds.

## Pre-publication checklist

- Test on a real Android device: create/import accounts, scan QR, TOTP accuracy, copy, lock/unlock, background/foreground behavior, encrypted backup and restore.
- Test cloud restore with a second device and the same cloud account. Do not claim fully automatic cross-device synchronization unless verified.
- Review the live privacy policy, data safety disclosures, account deletion route, store listing, app icon and screenshots.
- Ensure Play Console's target API level and testing eligibility requirements are satisfied at submission time.
- Keep a separate copy of recovery codes and original authenticator while testing.

