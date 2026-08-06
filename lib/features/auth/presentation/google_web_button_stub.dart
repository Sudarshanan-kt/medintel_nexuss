import 'package:flutter/widgets.dart';

import '../domain/auth_repository.dart' show GoogleWebCredential;
import 'google_web_button_style.dart';

/// Non-web platforms don't use this widget at all (see the auth screens —
/// they render their own button and call `signIn()` directly there, which is
/// reliable on Android/iOS). This stub only exists so the conditional import
/// in `google_web_button.dart` has something to resolve to when compiling
/// for those platforms, where `google_sign_in_web` isn't available.
Widget buildGoogleWebButton({
  required double size,
  required ValueChanged<GoogleWebCredential> onSignedIn,
  required GoogleWebButtonStyle style,
}) {
  return const SizedBox.shrink();
}
