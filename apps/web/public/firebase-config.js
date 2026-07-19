// Firebase Web config for push notifications.
//
// Fill these from your Firebase project:
//   apiKey, authDomain, projectId, messagingSenderId, appId
//     → Firebase console → Project settings → General → Your apps → Web app
//   vapidKey
//     → Project settings → Cloud Messaging → Web Push certificates (Key pair)
//
// These values are PUBLIC and safe to ship (the secret service-account key lives
// only on the server). This is a plain static file — edit it and redeploy just
// this file; no rebuild needed. `self` works in both the page and the service
// worker, which both read this.
self.__FIREBASE_CONFIG__ = {
    apiKey: '',
    authDomain: '',
    projectId: '',
    messagingSenderId: '',
    appId: '',
    vapidKey: '',
}
