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
  static const String forgotPasswordEndpoint = '/api/users/forgot-password';
  static const String resetPasswordEndpoint = '/api/users/reset-password';
  static const String validateResetTokenEndpoint =
      '/api/users/validate-reset-token';

  static const String resetLinkScheme = String.fromEnvironment(
    'PASSWORD_RESET_DEEPLINK_SCHEME',
    defaultValue: 'hermithome',
  );
  static const String resetLinkHost = String.fromEnvironment(
    'PASSWORD_RESET_DEEPLINK_HOST',
    defaultValue: 'reset-password',
  );

  static const String devicesEndpoint = '/api/devices';
  static const String deviceSchedulesEndpoint = '/api/devices/schedules';

  static String deviceByIdEndpoint(String deviceId) => '/api/devices/$deviceId';
  static String deviceStatusEndpoint(String deviceId) =>
      '/api/devices/$deviceId/status';
  static String deviceOverrideEndpoint(String deviceId) =>
      '/api/devices/$deviceId/override';
  static String deviceControlEndpoint(String deviceId) =>
      '/api/devices/$deviceId/control';

  static const String tokenKey = 'hh_jwt_token';
  static const String emailKey = 'hh_user_email';
  static const String userIdKey = 'hh_user_id';
  static const String accountCreatedAtKey = 'hh_user_created_at';
  static const String lastLoginAtKey = 'hh_last_login_at';

  static const Duration requestTimeout = Duration(seconds: 15);
}
