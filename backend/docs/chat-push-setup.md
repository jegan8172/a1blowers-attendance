# Chat push notifications

Set `FCM_SERVER_KEY` in the deployment environment to enable FCM message and attendance-card notifications. Do not commit the key. Devices register through `POST /api/chat/push-tokens`; muted conversations are excluded automatically. Without the key the chat API continues normally and sends no background push.
