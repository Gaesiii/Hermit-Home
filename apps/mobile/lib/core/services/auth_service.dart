// lib/core/services/auth_service.dart
//
// Changes from previous version
// ──────────────────────────────
// • A shared _handleException() method now logs the exact exception TYPE
//   (SocketException, TimeoutException, HandshakeException, etc.) in debug
//   mode so the real failure is visible in the console, not swallowed into
//   "An unexpected error occurred."
// • TimeoutException is caught explicitly with a clear user message.
// • HandshakeException (TLS failures) is caught explicitly.
// • The catch-all surfaces the runtimeType in debug builds so unknown
//   exception classes can be identified and handled specifically.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import '../models/auth_result.dart';

class AuthService {
  // ── Singleton ────────────────────────────────────────────────────────────────
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // ── Storage ──────────────────────────────────────────────────────────────────
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Internal helpers ─────────────────────────────────────────────────────────

  Uri _uri(String endpoint) => Uri.parse('${AppConstants.apiBaseUrl}$endpoint');

  Map<String, String> get _jsonHeaders => {
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.acceptHeader: 'application/json',
      };

  String _extractError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body['error'] as String?) ??
          'Unexpected error (${response.statusCode})';
    } catch (_) {
      return 'Server error (${response.statusCode})';
    }
  }

  // ── Shared exception → AuthResult converter ──────────────────────────────────
  //
  // Always prints the exact runtime type and message in debug mode.
  // Check your `flutter run` console — you will see the real exception there.
  //
  // Common types you will encounter:
  //   SocketException     → OS refused the connection. On Android this is almost
  //                         always caused by the cleartext HTTP policy blocking
  //                         your http:// request. Fix: network_security_config.xml
  //   TimeoutException    → server took longer than requestTimeout to respond.
  //   HandshakeException  → TLS error (certificate, protocol mismatch, etc.).
  //   http.ClientException→ error from the http package layer.
  //   FormatException     → response body was not valid JSON.
  AuthResult _handleException(Object e, StackTrace st) {
    if (kDebugMode) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║  AuthService exception                 ║');
      debugPrint('╠════════════════════════════════════════╣');
      debugPrint('║  type : ${e.runtimeType}');
      debugPrint('║  error: $e');
      debugPrint('╚════════════════════════════════════════╝');
      debugPrintStack(stackTrace: st, label: 'AuthService stack');
    }

    if (e is SocketException) {
      return const AuthResult.failure(
        'Cannot reach the server.\n'
        'Verify your dev server is running and that the IP in '
        'AppConstants.apiBaseUrl matches your machine\'s LAN IP.\n'
        '(Check the debug console for the exact OS error.)',
      );
    }

    if (e is TimeoutException) {
      return const AuthResult.failure(
        'Request timed out. Check that the server is responding.',
      );
    }

    if (e is HandshakeException) {
      return const AuthResult.failure(
        'TLS handshake failed. Use HTTPS for production, or verify '
        'network_security_config.xml allows your dev IP.',
      );
    }

    if (e is http.ClientException) {
      return const AuthResult.failure(
        'HTTP client error. Check your network connection.',
      );
    }

    if (e is FormatException) {
      return const AuthResult.failure(
        'Received an unexpected response from the server.',
      );
    }

    // Unknown exception — the type is printed above, so check the console.
    return AuthResult.failure(
      kDebugMode
          ? 'Unexpected ${e.runtimeType} — see debug console for details.'
          : 'An unexpected error occurred. Please try again.',
    );
  }

  // ── Public API ───────────────────────────────────────────────────────────────

  Future<AuthResult> register({
    required String email,
    required String password,
  }) async {
    try {
      final url = _uri(AppConstants.registerEndpoint);
      final body = jsonEncode({'email': email, 'password': password});

      if (kDebugMode) {
        debugPrint('🚀 POST $url  body=$body');
      }

      final response = await http
          .post(url, headers: _jsonHeaders, body: body)
          .timeout(AppConstants.requestTimeout);

      if (kDebugMode) {
        debugPrint('📦 ${response.statusCode}  body=${response.body}');
      }

      if (response.statusCode == 201) return const AuthResult.registerSuccess();
      return AuthResult.failure(_extractError(response));
    } catch (e, st) {
      return _handleException(e, st);
    }
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final url = _uri(AppConstants.loginEndpoint);
      final body = jsonEncode({'email': email, 'password': password});

      if (kDebugMode) {
        debugPrint('🚀 POST $url  body=$body');
      }

      final response = await http
          .post(url, headers: _jsonHeaders, body: body)
          .timeout(AppConstants.requestTimeout);

      if (kDebugMode) {
        debugPrint('📦 ${response.statusCode}  body=${response.body}');
      }

      if (response.statusCode == 200) {
        final bodyMap = jsonDecode(response.body) as Map<String, dynamic>;
        final token = bodyMap['token'] as String;
        final userMap = bodyMap['user'] as Map<String, dynamic>?;
        final userEmail = (userMap?['email'] as String?) ?? email;

        await _persistSession(token: token, email: userEmail);
        return AuthResult.loginSuccess(token: token, email: userEmail);
      }

      return AuthResult.failure(_extractError(response));
    } catch (e, st) {
      return _handleException(e, st);
    }
  }

  Future<bool> isLoggedIn() async =>
      (await _storage.read(key: AppConstants.tokenKey))?.isNotEmpty ?? false;

  Future<String?> getToken() => _storage.read(key: AppConstants.tokenKey);
  Future<String?> getEmail() => _storage.read(key: AppConstants.emailKey);

  Future<void> logout() async {
    await Future.wait([
      _storage.delete(key: AppConstants.tokenKey),
      _storage.delete(key: AppConstants.emailKey),
    ]);
  }

  Future<void> _persistSession({
    required String token,
    required String email,
  }) async {
    await Future.wait([
      _storage.write(key: AppConstants.tokenKey, value: token),
      _storage.write(key: AppConstants.emailKey, value: email),
    ]);
  }
}
