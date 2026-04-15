class AppConstants {
  AppConstants._();

  // Override at build/run time:
  // flutter run --dart-define=API_BASE_URL=https://your-api-domain
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://hermit-home.vercel.app',
  );

  static const String registerEndpoint = '/api/users/register';
  static const String loginEndpoint = '/api/users/login';

  static const String tokenKey = 'hh_jwt_token';
  static const String emailKey = 'hh_user_email';
  static const String userIdKey = 'hh_user_id';
  static const String accountCreatedAtKey = 'hh_user_created_at';
  static const String lastLoginAtKey = 'hh_last_login_at';

  static const Duration requestTimeout = Duration(seconds: 15);
}
