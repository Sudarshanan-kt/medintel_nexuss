// Web implementation using the browser Notifications API.
import 'dart:html' as html;

Future<bool> ensureNotificationPermission() async {
  try {
    if (!html.Notification.supported) return false;
    var perm = html.Notification.permission;
    if (perm != 'granted' && perm != 'denied') {
      perm = await html.Notification.requestPermission();
    }
    return perm == 'granted';
  } catch (_) {
    return false;
  }
}

void showDeviceNotification(String title, String body) {
  try {
    if (html.Notification.supported &&
        html.Notification.permission == 'granted') {
      html.Notification(title, body: body);
    }
  } catch (_) {/* ignore */}
}
