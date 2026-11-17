# Chat push notifications (FCM HTTP v1)

The chat backend uses the Firebase Admin SDK and FCM HTTP v1. It never uses `FCM_SERVER_KEY` or the legacy `https://fcm.googleapis.com/fcm/send` endpoint. Chat, attachments, attendance system cards, and attendance permission-decision messages continue to work when push is disabled or Firebase delivery fails.

## Required Firebase Console setup

1. Select the Firebase project that belongs to this application.
2. In Google Cloud Console for that project, enable **Firebase Cloud Messaging API**.
3. Register Android application id `com.a1blowers.attendance`, download `google-services.json`, and place it at `frontend/android/app/google-services.json`. It is intentionally ignored and must not be committed.
4. Register a Web app. Copy its public Firebase configuration into `frontend/web/firebase-config.js`, replacing its placeholders. This is public client configuration, not an Admin SDK credential.
5. In Firebase Console > Project settings > Cloud Messaging, create a **Web Push certificate** and use its public VAPID key when building the web app.
6. If iOS is distributed, register its bundle id, download `GoogleService-Info.plist`, add it to `frontend/ios/Runner/` in Xcode (Runner target membership checked), and configure an APNs authentication key/certificate in Firebase Console > Project settings > Cloud Messaging.

## Backend credential setup

The backend chooses credentials in this order:

1. `FIREBASE_SERVICE_ACCOUNT_JSON`: the complete service-account JSON, stored only in the deployment platform's secret manager.
2. `GOOGLE_APPLICATION_CREDENTIALS`: an absolute path to a securely mounted service-account JSON file.
3. `FIREBASE_USE_APPLICATION_DEFAULT_CREDENTIALS=true`: explicit Cloud Run / Workload Identity opt-in, using its runtime service account and no downloaded key.
4. No credential: push is disabled safely; all chat and attendance APIs still work.

Never commit a service-account JSON, private key, `.env`, or either environment variable's value. The repository ignores commonly named service-account files. If organization policy prevents creating private keys, use a runtime service account/Workload Identity with Application Default Credentials instead of weakening that policy.

### Cloud Run with Secret Manager

Create a Secret Manager secret named `FIREBASE_SERVICE_ACCOUNT_JSON`, grant the Cloud Run runtime service account access to that secret, and expose it to the `attendance-api` container as the environment variable of the same name. Do not place the JSON into a Cloud Run command, source file, GitHub Actions log, or shell history. Redeploy after linking the secret.

### Cloud Run without a private key (recommended)

Set `FIREBASE_USE_APPLICATION_DEFAULT_CREDENTIALS=true` on `attendance-api`,
then grant its runtime service account the minimum Firebase Cloud Messaging
permissions required by your organization. Cloud Run supplies short-lived
Application Default Credentials automatically; no secret JSON is created,
stored, or mounted.

For local development, keep the JSON outside the repository and set only one of:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\secure\firebase-admin.json'
# Or set FIREBASE_SERVICE_ACCOUNT_JSON through a private local secret manager.
```

Restart the backend after changing a credential. Do not put these values in `backend/.env` if that file could be shared or uploaded.

## Web build configuration

Supply the public Firebase values at build time:

```powershell
flutter build web --release `
  --dart-define=FIREBASE_WEB_API_KEY=... `
  --dart-define=FIREBASE_WEB_APP_ID=... `
  --dart-define=FIREBASE_WEB_MESSAGING_SENDER_ID=... `
  --dart-define=FIREBASE_WEB_PROJECT_ID=... `
  --dart-define=FIREBASE_WEB_AUTH_DOMAIN=... `
  --dart-define=FIREBASE_WEB_STORAGE_BUCKET=... `
  --dart-define=FIREBASE_WEB_VAPID_KEY=...
```

`FIREBASE_WEB_VAPID_KEY` and the other web values are public client configuration, not service-account credentials. Deploy both `firebase-messaging-sw.js` and `firebase-config.js` from the web build output.

## Expected behavior and troubleshooting

- The app requests notification permission, registers its FCM token at `POST /api/chat/push-tokens` after login, and re-registers refreshed tokens.
- A muted participant receives no notification. The sender is excluded.
- Invalid or unregistered FCM tokens are removed from `chat_push_tokens`.
- A notification contains `conversationId` and `type`; opening it takes the user to the chat conversation.
- **No credential configured:** the backend logs that Firebase push is disabled; chat still succeeds.
- **Permission denied:** enable notifications in browser/site settings or Android app settings, then sign in again.
- **No web push:** verify VAPID, browser permission, HTTPS, and `/firebase-messaging-sw.js` returns HTTP 200.
- **No Android push:** verify the final APK contains the correct `google-services.json`, then sign out/in after granting notification permission.
