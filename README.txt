FRESH START - Loyalty Wallet SA

This is a clean Flutter starter source intended for building an Android debug APK using GitHub Actions.

Files to upload into your GitHub repository (root):
- pubspec.yaml
- lib/main.dart
- .github/workflows/build-apk.yml

Build:
1. Commit/push files to branch main.
2. Open GitHub repo > Actions.
3. Select Build Android APK and wait for green success.
4. Open the successful run; download artifact Loyalty-Wallet-SA-APK.
5. Extract the downloaded ZIP and install app-debug.apk (allow installs from browser/files if Android asks).

MVP features:
- Scan barcode/QR values using phone camera.
- Store card names, raw scanned values, category, and manually-entered balance.
- Search saved cards.
- Tap card to display a large code (QR fallback for formats not handled).
- Favorite cards.
- Local storage uses Flutter Secure Storage.

Notes:
This is an early MVP. PIN/biometric lock is not yet enforced on app startup; the security screen is only a test entry point. Card code regeneration depends on the format and data validity. Test on-device before relying on it at checkout.
