// Hand-written (not via `flutterfire configure`) from the Firebase console's
// Android app config (google-services.json) and Web app config. Only
// Android and Web are set up — this project has no ios/macos platform yet.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for '
          '$defaultTargetPlatform — only Android and Web are set up.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAtni41m0qPOA83T3dlcXj8h-I9ElnDdCQ',
    appId: '1:691219519209:web:dcf4b8f8ff764061340278',
    messagingSenderId: '691219519209',
    projectId: 'medintel-nexus',
    authDomain: 'medintel-nexus.firebaseapp.com',
    storageBucket: 'medintel-nexus.firebasestorage.app',
    measurementId: 'G-B8SFYXEFZ2',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAQeZVsW27oN6lkhVusbvx6l2Ok-CFcx3M',
    appId: '1:691219519209:android:21bfc9694fc426b2340278',
    messagingSenderId: '691219519209',
    projectId: 'medintel-nexus',
    storageBucket: 'medintel-nexus.firebasestorage.app',
  );
}
