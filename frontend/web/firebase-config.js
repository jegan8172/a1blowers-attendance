// Firebase web configuration is public client metadata, not a service-account
// credential. Replace these placeholders from Firebase Console > Project
// settings > Your apps > Web app before building the web application.
self.firebaseConfig = {
  apiKey: 'REPLACE_WITH_WEB_API_KEY',
  authDomain: 'REPLACE_WITH_AUTH_DOMAIN',
  projectId: 'REPLACE_WITH_PROJECT_ID',
  storageBucket: 'REPLACE_WITH_STORAGE_BUCKET',
  messagingSenderId: 'REPLACE_WITH_MESSAGING_SENDER_ID',
  appId: 'REPLACE_WITH_WEB_APP_ID',
  measurementId: ''
};
