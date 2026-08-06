import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui_web' as ui_web;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_identity_services_web/id.dart' as gis;
import 'package:google_identity_services_web/loader.dart' as gis_loader;
import 'package:web/web.dart' as web;

import '../../../core/constants/google_auth_config.dart';
import '../domain/auth_repository.dart' show GoogleWebCredential;
import 'google_web_button_style.dart';

/// The actual web implementation, only ever compiled when the app targets
/// web (see the conditional import in `google_web_button.dart`).
///
/// This drives Google's Identity Services JS API directly rather than going
/// through `google_sign_in`/`google_sign_in_web`'s `GoogleSignIn().signIn()`
/// or their `renderButton()` wrapper, for two reasons:
///  1. Only Google's own rendered button (the credential/One Tap flow) can
///     return an ID token on web at all — the tap-to-`signIn()` popup flow
///     structurally can't (google_sign_in_web's own deprecation notice says
///     so explicitly) — which is exactly what Supabase's `signInWithIdToken`
///     needs.
///  2. Google's JS SDK now defaults to FedCM, which embeds a `nonce` claim
///     in that ID token — and Supabase requires the *same raw* nonce be
///     passed alongside the token, or it rejects the exchange with "Passed
///     nonce and nonce in id_token should either both exist or not." The
///     `google_sign_in`/`google_sign_in_web` plugins initialize their GIS
///     client internally with no nonce and never expose one, so there is no
///     way to get a matching value back out of them. Calling
///     `google.accounts.id` ourselves means we choose the nonce, so we can
///     hand the same one to Supabase.
Widget buildGoogleWebButton({
  required double size,
  required ValueChanged<GoogleWebCredential> onSignedIn,
  required GoogleWebButtonStyle style,
}) {
  return _GoogleWebButton(size: size, onSignedIn: onSignedIn, style: style);
}

// The GIS `<script>` tag must only ever be injected once per page, however
// many `_GoogleWebButton`s get mounted over the app's lifetime (e.g.
// navigating from the login screen to the sign-up screen) — caching the
// load future across instances keeps that to a single injection.
Future<void>? _gisSdkFuture;
Future<void> _ensureGisSdkLoaded() =>
    _gisSdkFuture ??= gis_loader.loadWebSdk();

class _GoogleWebButton extends StatefulWidget {
  const _GoogleWebButton({
    required this.size,
    required this.onSignedIn,
    required this.style,
  });
  final double size;
  final ValueChanged<GoogleWebCredential> onSignedIn;
  final GoogleWebButtonStyle style;

  @override
  State<_GoogleWebButton> createState() => _GoogleWebButtonState();
}

class _GoogleWebButtonState extends State<_GoogleWebButton> {
  // A fresh nonce per mounted button, never reused across sign-in attempts.
  final String _rawNonce = _generateNonce();
  late final String _viewType = 'google-web-button-${identityHashCode(this)}';
  bool _handled = false;

  // Loads the GIS SDK (once, page-wide, see `_ensureGisSdkLoaded`), then
  // registers this button's own platform-view factory — which is what
  // actually calls `initialize()` + `renderButton()` once the browser asks
  // for the view. Gating the whole widget on this (via FutureBuilder below)
  // is what prevents the historical "GIS Client not initialized" crash from
  // rendering the button before the SDK script has finished loading.
  late final Future<void> _ready = _ensureGisSdkLoaded().then((_) {
    if (!mounted) return;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final container =
          web.document.createElement('div') as web.HTMLDivElement;
      gis.id.initialize(
        gis.IdConfiguration(
          client_id: GoogleAuthConfig.webClientId,
          nonce: _hashNonce(_rawNonce),
          callback: _handleCredential,
          use_fedcm_for_prompt: true,
        ),
      );
      gis.id.renderButton(container, _buttonConfig());
      return container;
    });
  });

  void _handleCredential(gis.CredentialResponse response) {
    if (_handled) return;
    final idToken = response.credential;
    if (idToken == null) return;
    _handled = true;
    widget.onSignedIn(
      GoogleWebCredential(idToken: idToken, nonce: _rawNonce),
    );
  }

  gis.GsiButtonConfiguration _buttonConfig() {
    switch (widget.style) {
      case GoogleWebButtonStyle.iconCircle:
        return gis.GsiButtonConfiguration(
          type: gis.ButtonType.icon,
          shape: gis.ButtonShape.pill,
          theme: gis.ButtonTheme.outline,
        );
      case GoogleWebButtonStyle.fullWidthStandard:
        return gis.GsiButtonConfiguration(
          type: gis.ButtonType.standard,
          shape: gis.ButtonShape.rectangular,
          theme: gis.ButtonTheme.outline,
          text: gis.ButtonText.continue_with,
          width: 300,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        final ready = snapshot.connectionState == ConnectionState.done;
        final child = ready
            ? HtmlElementView(viewType: _viewType)
            : const SizedBox.shrink();
        switch (widget.style) {
          case GoogleWebButtonStyle.iconCircle:
            return ClipOval(
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: child,
              ),
            );
          case GoogleWebButtonStyle.fullWidthStandard:
            return SizedBox(
              width: double.infinity,
              height: widget.size,
              child: child,
            );
        }
      },
    );
  }
}

/// Generates a cryptographically random raw nonce. [_hashNonce] of this same
/// string is what's handed to Google; the raw string itself is what's handed
/// to Supabase, which hashes it the same way to verify the two match.
String _generateNonce([int length = 32]) {
  const charset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

String _hashNonce(String raw) => sha256.convert(utf8.encode(raw)).toString();
