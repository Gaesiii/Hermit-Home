class AuthResult {
  final bool isSuccess;
  final String? token;
  final String? email;
  final String? userId;
  final DateTime? createdAt;
  final String? errorMessage;

  const AuthResult._({
    required this.isSuccess,
    this.token,
    this.email,
    this.userId,
    this.createdAt,
    this.errorMessage,
  });

  const AuthResult.loginSuccess({
    required String token,
    required String email,
    String? userId,
    DateTime? createdAt,
  }) : this._(
          isSuccess: true,
          token: token,
          email: email,
          userId: userId,
          createdAt: createdAt,
        );

  const AuthResult.registerSuccess() : this._(isSuccess: true);

  const AuthResult.failure(String message)
      : this._(isSuccess: false, errorMessage: message);
}
