// lib/core/constants/app_constants.dart
//
// Single source of truth for every magic string in the app.
// Change API_BASE_URL here to point at your Vercel deployment.

class AppConstants {
  AppConstants._(); // non-instantiable

  // ── API ─────────────────────────────────────────────────────────────────────
  // Development  : http://localhost:3000
  // Production   : https://hermit.vercel.app   (replace with your real domain)
  //static const String apiBaseUrl = 'https://hermit.vercel.app';
// or for local dev:
  //static const String apiBaseUrl = 'http://10.0.2.2:3000';
  static const String apiBaseUrl = 'http://192.168.2.78:3000';

  static const String registerEndpoint = '/api/users/register';
  static const String loginEndpoint = '/api/users/login';

  // ── Secure Storage Keys ─────────────────────────────────────────────────────
  static const String tokenKey = 'hh_jwt_token';
  static const String emailKey = 'hh_user_email';

  // ── Timeouts ────────────────────────────────────────────────────────────────
  static const Duration requestTimeout = Duration(seconds: 15);
}
