// Firebase Cloud Messaging service worker — handles push delivery while the
// web app is in the background/closed. Required for web push to work at
// all; foreground messages are handled in Dart via FirebaseMessaging.onMessage
// instead (see lib/features/push/data/push_service.dart).
importScripts('https://www.gstatic.com/firebasejs/10.13.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAtni41m0qPOA83T3dlcXj8h-I9ElnDdCQ',
  authDomain: 'medintel-nexus.firebaseapp.com',
  projectId: 'medintel-nexus',
  storageBucket: 'medintel-nexus.firebasestorage.app',
  messagingSenderId: '691219519209',
  appId: '1:691219519209:web:dcf4b8f8ff764061340278',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || 'MedIntel Nexus';
  const options = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
  };
  self.registration.showNotification(title, options);
});
