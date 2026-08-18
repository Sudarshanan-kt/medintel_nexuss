// Web implementation using the browser Notifications API.
//
// Written against `package:web` + `dart:js_interop` rather than `dart:html`,
// which is deprecated and absent from a wasm build — the same wasm build the
// analyzer already warns about elsewhere in this project.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Whether this browser exposes the Notifications API at all.
///
/// Checked through the global object rather than by touching
/// [web.Notification], because static interop compiles to a bare property
/// access that throws where the API is missing — Safari in an insecure
/// context, and any browser inside a cross-origin iframe.
bool get _supported => globalContext.has('Notification');

Future<bool> ensureNotificationPermission() async {
  try {
    if (!_supported) return false;

    final current = web.Notification.permission;
    if (current == 'granted') return true;
    // 'denied' is the user's standing answer; asking again is a no-op that
    // resolves straight back to 'denied'.
    if (current == 'denied') return false;

    final granted = await web.Notification.requestPermission().toDart;
    return granted.toDart == 'granted';
  } catch (_) {
    return false;
  }
}

void showDeviceNotification(String title, String body) {
  try {
    if (!_supported) return;
    if (web.Notification.permission != 'granted') return;
    web.Notification(title, web.NotificationOptions(body: body));
  } catch (_) {
    // A notification that can't be shown is not worth failing a dose log for.
  }
}
