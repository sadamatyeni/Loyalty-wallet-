# Build APK using GitHub Actions from your Android phone

This package contains Flutter source + an automatic cloud build workflow. GitHub Actions generates the Android platform scaffold and builds a debug APK.

## Phone-only instructions
1. Sign in/create a GitHub account at https://github.com
2. Create a NEW repository named `loyalty-wallet-sa`. Public is easiest for Actions minutes, but private also works if your account's Actions minutes are available.
3. On the repo page, tap **Add file → Upload files** and upload the contents of this ZIP (including `.github/workflows/build-apk.yml`). Make sure the workflow path is exactly `.github/workflows/build-apk.yml`.
   - If the mobile upload UI hides dotfolders, use GitHub's web desktop mode or create the workflow file directly using Add file → Create new file and enter the path `.github/workflows/build-apk.yml`.
4. Commit the files to the `main` branch.
5. Open the repo's **Actions** tab. If GitHub asks to enable Actions, enable them.
6. Choose **Build Loyalty Wallet SA APK**, press **Run workflow**, then **Run workflow** again.
7. Wait for it to finish green. Open the run and download the artifact named `Loyalty-Wallet-SA-debug-apk`. GitHub downloads an artifact ZIP; unzip it and install `app-debug.apk`.
8. If Android blocks installation, allow **Install unknown apps** for the browser/files app that opened the APK, then retry.

## Important
- Debug APK is for testing, not store release.
- GitHub Actions can have usage limits; if build fails, open the run and share its error log/screenshots with me.
- This project generates Android scaffolding during the cloud build because this starter archive doesn't include the full generated Android folder.
- Do not create or share a GitHub personal access token for this method.
