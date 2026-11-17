'use strict';

let admin;
let initializationAttempted = false;
let messaging;

function initializeFirebaseAdmin() {
  if (initializationAttempted) return messaging || null;
  initializationAttempted = true;
  try {
    admin = require('firebase-admin');
    let credential;
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      let serviceAccount;
      try { serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON); }
      catch (_) { console.warn('Firebase push disabled: FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON.'); return null; }
      credential = admin.credential.cert(serviceAccount);
    } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      // applicationDefault() reads the securely mounted service-account file.
      credential = admin.credential.applicationDefault();
    } else if (process.env.FIREBASE_USE_APPLICATION_DEFAULT_CREDENTIALS === 'true') {
      // Explicit Cloud Run / Workload Identity opt-in. No downloaded key is
      // used; Google supplies short-lived credentials for the runtime identity.
      credential = admin.credential.applicationDefault();
    } else {
      console.info('Firebase push disabled: no Firebase credential is configured.');
      return null;
    }
    if (!admin.apps.length) admin.initializeApp({ credential });
    messaging = admin.messaging();
    console.info('Firebase Admin Messaging initialized.');
    return messaging;
  } catch (error) {
    console.warn('Firebase push disabled: Admin SDK initialization failed.', { code: error?.code, message: error?.message });
    return null;
  }
}

function getMessaging() { return messaging || initializeFirebaseAdmin(); }

module.exports = { getMessaging, initializeFirebaseAdmin };
