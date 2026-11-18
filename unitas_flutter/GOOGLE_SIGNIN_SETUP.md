# Google Sign-In Setup (Android & Backend)

Unitas uses `google_sign_in` (`^7.2.0`) with Android Credential Manager (no `google-services.json` required) to obtain a Google ID token and exchange it at `POST /api/auth/google`.

## 1. Android App Identifiers

- **Package Name / Application ID**: `com.unitas.unitas_flutter` (defined in `android/app/build.gradle.kts`)
- **Minimum SDK**: `24` (required by `google_sign_in_android` and `flutter_secure_storage`)

## 2. Obtain Your Android Signing SHA-1 Fingerprint

### Debug build (local development)
Run from `unitas_flutter/`:
```bash
cd android
./gradlew signingReport
```
Or inspect your debug keystore directly:
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```
Copy the **SHA1** fingerprint (e.g. `AA:BB:CC:...`).

### Release / Play Store build
- If using your own upload keystore: run `keytool -list -v -keystore <path-to-release.keystore> -alias <alias>` and copy **SHA1**.
- If using Google Play App Signing: also copy the **App signing key certificate SHA-1** from **Play Console → Setup → App integrity**.

## 3. Create OAuth 2.0 Clients in Google Cloud Console

Open [Google Cloud Console → APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials) (configure the **OAuth consent screen** first if you haven't already):

1. **Create an Android OAuth Client ID** (required by Android Credential Manager to authorize this app):
   - Application type: **Android**
   - Package name: `com.unitas.unitas_flutter`
   - SHA-1 certificate fingerprint: paste your debug (and add another Android client for release/Play) SHA-1.
   - *Note*: You do **not** put this Android Client ID in `.env`.

2. **Create a Web Application OAuth Client ID** (used as `serverClientId` to mint the ID token for the backend):
   - Application type: **Web application**
   - Copy the generated **Client ID** (`xxxxx.apps.googleusercontent.com`).

## 4. Configure Environment Variables

### Flutter (`unitas_flutter`)
Set `GOOGLE_SERVER_CLIENT_ID` to the **Web application Client ID** via either:
- `unitas_flutter/.env` (copy from `.env.example`):
  ```env
  BACKEND_URL=https://unitas-beta.vercel.app
  GOOGLE_SERVER_CLIENT_ID=xxxxx.apps.googleusercontent.com
  ```
- **OR** pass it at build/run time with `--dart-define`:
  ```bash
  flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxxx.apps.googleusercontent.com
  ```

### Backend (`unitas_backend`)
Set `GOOGLE_CLIENT_ID` (on Vercel / `.env`) to the **exact same Web application Client ID**, because the backend verifies the ID token `aud` claim against `GOOGLE_CLIENT_ID` (and optional comma-separated `GOOGLE_SERVER_CLIENT_IDS`).

Also make sure database migration `unitas_backend/supabase/migrations/005_google_auth.sql` has been applied in Supabase.

## 5. Troubleshooting

- **`clientConfigurationError` / missing `serverClientId`**: Verify `GOOGLE_SERVER_CLIENT_ID` is set in `.env` or passed via `--dart-define`.
- **Sign-in immediately reports `canceled` after selecting an account**: On Android Credential Manager, this usually means the **Android OAuth Client** is missing, the package name isn't `com.unitas.unitas_flutter`, or the build's **SHA-1** fingerprint doesn't match the one registered in Google Cloud Console.
- **Backend returns `401` (`wrong audience`) or `503`**: Confirm backend `GOOGLE_CLIENT_ID` matches Flutter's `GOOGLE_SERVER_CLIENT_ID` (the **Web** Client ID, not the Android Client ID).
