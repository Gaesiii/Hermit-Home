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

  static const Duration requestTimeout = Duration(seconds: 15);
}
