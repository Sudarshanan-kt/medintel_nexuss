import 'package:flutter/widgets.dart';

import '../domain/auth_repository.dart' show GoogleWebCredential;
import 'google_web_button_stub.dart'
    if (dart.library.js_interop) 'google_web_button_web.dart' as impl;
import 'google_web_button_style.dart';

export '../domain/auth_repository.dart' show GoogleWebCredential;
export 'google_web_button_style.dart' show GoogleWebButtonStyle;

/// Google's own rendered "Sign in with Google" button — used only on the web
/// build of the sign-in screens.
///
/// Why not the same tap-to-`signIn()` button mobile uses? On web, that popup
/// flow can't reliably produce an ID token (see google_sign_in_web's own
/// deprecation notice), which is exactly what Supabase's Google provider
/// needs. This renders Google's official button (the credential/One Tap
/// flow) instead, styled as an icon-only circle to match this app's other
/// social buttons as closely as Google's UI allows. [onSignedIn] fires with
/// the resulting [GoogleWebCredential] once the user completes it.
class GoogleWebButton extends StatelessWidget {
  const GoogleWebButton({
    super.key,
    required this.size,
    required this.onSignedIn,
    this.style = GoogleWebButtonStyle.iconCircle,
  });

  /// For [GoogleWebButtonStyle.iconCircle], the circle's diameter. For
  /// [GoogleWebButtonStyle.fullWidthStandard], the button's height.
  final double size;
  final ValueChanged<GoogleWebCredential> onSignedIn;
  final GoogleWebButtonStyle style;

  @override
  Widget build(BuildContext context) {
    return impl.buildGoogleWebButton(
      size: size,
      onSignedIn: onSignedIn,
      style: style,
    );
  }
}
