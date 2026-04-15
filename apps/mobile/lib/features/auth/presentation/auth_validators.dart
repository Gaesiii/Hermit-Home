// lib/features/auth/presentation/auth_validators.dart
//
// Pure, stateless validation functions for auth form fields.
//
// These functions follow the [FormFieldValidator<String>] signature expected
// by [TextFormField.validator], so they can be passed directly without
// wrapping. They are also fully testable without any Flutter widget machinery.
//
// The rules here deliberately mirror the backend's validation logic so that
// any input rejected locally will also be rejected by the server, and vice
// versa — preventing a class of "client says valid, server says invalid" bugs.

/// Validates that [value] is a non-empty string containing a plausible
/// email address.
///
/// Returns a user-facing error string on failure, or `null` on success.
///
/// Pattern: `something @ something . something`
/// This is intentionally permissive — the server applies stricter RFC-5322
/// checks. Our goal is only to catch obvious typos before a network round trip.
String? validateEmail(String? value) {
  final String email = value?.trim() ?? '';

  if (email.isEmpty) {
    return 'Email address is required.';
  }

  // Quick sanity check — must have exactly one @ with non-empty parts on both
  // sides, and the domain must contain at least one dot.
  final RegExp emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  if (!emailRe.hasMatch(email)) {
    return 'Please enter a valid email address (e.g. you@example.com).';
  }

  return null;
}

/// Validates that [value] meets the minimum password requirements.
///
/// Returns a user-facing error string on failure, or `null` on success.
///
/// Current rules:
///   • Non-empty.
///   • At least 8 characters (matches the bcrypt minimum on the server).
///
/// If the backend's password policy changes, update this function and the
/// matching [PasswordField] validator in `auth_widgets.dart` together.
String? validatePassword(String? value) {
  final String password = value ?? '';

  if (password.isEmpty) {
    return 'Password is required.';
  }

  if (password.length < 8) {
    return 'Password must be at least 8 characters.';
  }

  return null;
}

/// Validates that the confirm-password field [value] matches [original].
///
/// Intended to be composed with [validatePassword] on the register screen:
///
/// ```dart
/// validator: (value) =>
///     validatePassword(value) ??
///     validateConfirmPassword(value, _passwordController.text),
/// ```
///
/// Returns a user-facing error string on mismatch, or `null` when they match.
String? validateConfirmPassword(String? value, String original) {
  if (value != original) {
    return 'Passwords do not match.';
  }
  return null;
}
