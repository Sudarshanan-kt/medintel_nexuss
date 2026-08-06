// Cross-platform-safe notification facade. Uses the Web Notifications API on
// web; a no-op everywhere else. Conditional import keeps mobile/desktop builds
// compiling even though the implementation uses dart:html.
import 'notification_api_stub.dart'
    if (dart.library.html) 'notification_api_web.dart' as impl;

/// Asks the user/browser for notification permission. Safe to call repeatedly.
Future<bool> ensureNotificationPermission() => impl.ensureNotificationPermission();

/// Shows a notification immediately (if permitted).
void showDeviceNotification(String title, String body) =>
    impl.showDeviceNotification(title, body);
