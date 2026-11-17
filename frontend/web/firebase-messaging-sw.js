// FCM requires this file at the web application's root for background push.
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');
importScripts('./firebase-config.js');

if (self.firebaseConfig && !String(self.firebaseConfig.apiKey || '').startsWith('REPLACE_')) {
  firebase.initializeApp(self.firebaseConfig);
  const messaging = firebase.messaging();
  messaging.onBackgroundMessage((payload) => {
    const data = payload.data || {};
    self.registration.showNotification(payload.notification?.title || 'GoDigital Attendance', {
      body: payload.notification?.body || 'You have a new update.',
      data: { conversationId: data.conversationId || '' }
    });
  });
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const conversationId = event.notification.data?.conversationId;
  const suffix = conversationId ? `?conversationId=${encodeURIComponent(conversationId)}` : '';
  event.waitUntil(clients.openWindow(`/${suffix}`));
});
