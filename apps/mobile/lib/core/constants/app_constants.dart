class AppConstants {
  AppConstants._();

  // Override at build/run time:
  // flutter run --dart-define=API_BASE_URL=https://your-api-domain
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://hermit-home.vercel.app',
  );

  static const String registerEndpoint = '/api/auth?action=register';
  static const String loginEndpoint = '/api/auth?action=login';

  static const String devicesEndpoint = '/api/devices';
  static const String deviceSchedulesEndpoint = '/api/devices/schedules';

  static String deviceByIdEndpoint(String deviceId) => '/api/devices/$deviceId';
  static String deviceStatusEndpoint(String deviceId) =>
      '/api/devices/$deviceId/data?type=latest';
  static String deviceTelemetryEndpoint(String deviceId, {int limit = 30}) =>
      '/api/devices/$deviceId/data?type=history&limit=$limit';
  static String deviceOverrideEndpoint(String deviceId) =>
      '/api/devices/$deviceId/action?type=override';
  static String deviceControlEndpoint(String deviceId) =>
      '/api/devices/$deviceId/action?type=control';

  static const String tokenKey = 'hh_jwt_token';
  static const String emailKey = 'hh_user_email';
  static const String userIdKey = 'hh_user_id';
  static const String accountCreatedAtKey = 'hh_user_created_at';
  static const String lastLoginAtKey = 'hh_last_login_at';

  static const Duration requestTimeout = Duration(seconds: 15);
}
