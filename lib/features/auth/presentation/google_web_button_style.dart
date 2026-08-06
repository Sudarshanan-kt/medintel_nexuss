/// How a [GoogleWebButton] should look. A tiny standalone file (rather than
/// living in `google_web_button.dart` itself) so both the web and non-web
/// implementation files can reference it without a circular import — those
/// two are conditionally imported *by* `google_web_button.dart`.
enum GoogleWebButtonStyle {
  /// Icon-only circle — matches this app's other small social buttons.
  iconCircle,

  /// Full-width "Continue with Google" button with text.
  fullWidthStandard,
}
