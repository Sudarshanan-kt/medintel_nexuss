// Non-web fallback — notifications are a no-op.
Future<bool> ensureNotificationPermission() async => false;

void showDeviceNotification(String title, String body) {}
