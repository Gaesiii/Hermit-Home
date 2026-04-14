// lib/core/models/auth_result.dart
//
// A discriminated-union-style result type for AuthService calls.
// Every method returns AuthResult — callers check `isSuccess` and then
// either read `token`/`email` or display `errorMessage`.

class AuthResult {
  /// True when the API returned the expected 2xx status code.
  final bool isSuccess;

  /// Set on a successful login — the raw JWT string from the API response.
  final String? token;

  /// Set on a successful login — the user's email extracted from the response.
  final String? email;

  /// Human-readable error message ready to drop into a SnackBar.
  /// Non-null whenever [isSuccess] is false.
  final String? errorMessage;

  const AuthResult._({
    required this.isSuccess,
    this.token,
    this.email,
    this.errorMessage,
  });

  // ── Named constructors ───────────────────────────────────────────────────────

  /// Successful login — carries the token and email.
  const AuthResult.loginSuccess({required String token, required String email})
      : this._(isSuccess: true, token: token, email: email);

  /// Successful registration — no token needed, user must log in next.
  const AuthResult.registerSuccess() : this._(isSuccess: true);

  /// Any failure path — carries a message for the UI.
  const AuthResult.failure(String message)
      : this._(isSuccess: false, errorMessage: message);
}
