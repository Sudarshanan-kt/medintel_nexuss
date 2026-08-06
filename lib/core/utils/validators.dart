/// Form validators. Returns `null` when valid, an error string otherwise.
abstract final class Validators {
  static final RegExp _email =
      RegExp(r'^[\w.\-+]+@([\w\-]+\.)+[\w\-]{2,}$');
  static final RegExp _phone = RegExp(r'^\d{7,15}$');
  static final RegExp _upper = RegExp(r'[A-Z]');
  static final RegExp _digit = RegExp(r'[0-9]');

  static String? phone(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'\s|-'), '');
    if (v.isEmpty) return 'Enter your mobile number';
    if (!_phone.hasMatch(v)) return 'Enter a valid mobile number';
    return null;
  }

  static String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter your email';
    if (!_email.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// Production-strength password: ≥8 chars, at least one uppercase, one digit.
  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter your password';
    if (v.length < 8) return 'Password must be at least 8 characters';
    if (!_upper.hasMatch(v)) return 'Include at least one uppercase letter';
    if (!_digit.hasMatch(v)) return 'Include at least one number';
    return null;
  }

  /// Validates that [value] matches [original] (for confirm-password fields).
  static String? Function(String?) confirmPassword(String original) {
    return (String? value) {
      final v = value ?? '';
      if (v.isEmpty) return 'Please confirm your password';
      if (v != original) return 'Passwords do not match';
      return null;
    };
  }

  static String? fullName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter your full name';
    if (v.length < 2) return 'Name is too short';
    return null;
  }

  static String? otp(String? value, int length) {
    final v = value ?? '';
    if (v.length != length) return 'Enter the $length-digit code';
    if (!RegExp(r'^\d+$').hasMatch(v)) return 'Code must be digits only';
    return null;
  }

  static String? required(String? value, [String field = 'This field']) {
    if ((value ?? '').trim().isEmpty) return '$field is required';
    return null;
  }
}
