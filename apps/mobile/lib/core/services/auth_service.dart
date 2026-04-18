import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import '../models/auth_result.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

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

  String? _readNonEmptyString(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  DateTime? _readIsoDate(Object? value) {
    final raw = _readNonEmptyString(value);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  AuthResult _handleException(Object e, StackTrace st) {
    if (kDebugMode) {
      debugPrint('AuthService error type=${e.runtimeType} error=$e');
      debugPrintStack(stackTrace: st);
    }

    if (e is SocketException) {
      return const AuthResult.failure(
        'Cannot reach server. Check API_BASE_URL and network connection.',
      );
    }

    if (e is TimeoutException) {
      return const AuthResult.failure(
        'Request timed out. Please try again.',
      );
    }

    if (e is HandshakeException) {
      return const AuthResult.failure(
        'TLS handshake failed. Verify HTTPS/certificate setup.',
      );
    }

    if (e is http.ClientException) {
      return const AuthResult.failure('HTTP client error.');
    }

    if (e is FormatException) {
      return const AuthResult.failure('Unexpected server response format.');
    }

    return AuthResult.failure(
      kDebugMode
          ? 'Unexpected ${e.runtimeType}. Check debug console.'
          : 'An unexpected error occurred. Please try again.',
    );
  }

  Future<AuthResult> register({
    required String email,
    required String password,
  }) async {
    try {
      final url = _uri(AppConstants.registerEndpoint);
      final body = jsonEncode({'email': email, 'password': password});

      final response = await http
          .post(url, headers: _jsonHeaders, body: body)
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 201) {
        return const AuthResult.registerSuccess();
      }

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

      final response = await http
          .post(url, headers: _jsonHeaders, body: body)
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode != 200) {
        return AuthResult.failure(_extractError(response));
      }

      final bodyMap = jsonDecode(response.body) as Map<String, dynamic>;
      final token = _readNonEmptyString(bodyMap['token']);
      if (token == null) {
        return const AuthResult.failure('Missing token in login response.');
      }

      final userMap = bodyMap['user'];
      final userData = userMap is Map<String, dynamic> ? userMap : null;

      final normalizedEmail = _readNonEmptyString(userData?['email']) ?? email;
      final userId = _readNonEmptyString(userData?['_id']);
      final createdAt = _readIsoDate(userData?['createdAt']);
      final lastLoginAt = DateTime.now();

      await _persistSession(
        token: token,
        email: normalizedEmail,
        userId: userId,
        accountCreatedAt: createdAt,
        lastLoginAt: lastLoginAt,
      );

      return AuthResult.loginSuccess(
        token: token,
        email: normalizedEmail,
        userId: userId,
        createdAt: createdAt,
      );
    } catch (e, st) {
      return _handleException(e, st);
    }
  }

  Future<AuthResult> forgotPassword({
    required String email,
  }) async {
    try {
      final url = _uri(AppConstants.forgotPasswordEndpoint);
      final body = jsonEncode({'email': email});

      final response = await http
          .post(url, headers: _jsonHeaders, body: body)
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        return const AuthResult.success();
      }

      return AuthResult.failure(_extractError(response));
    } catch (e, st) {
      return _handleException(e, st);
    }
  }

  Future<AuthResult> validateResetToken({
    required String token,
  }) async {
    try {
      final url = _uri(AppConstants.validateResetTokenEndpoint);
      final body = jsonEncode({'token': token});

      final response = await http
          .post(url, headers: _jsonHeaders, body: body)
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final bodyMap = jsonDecode(response.body) as Map<String, dynamic>;
        final accountHint = _readNonEmptyString(bodyMap['accountHint']);
        return AuthResult.resetTokenValidated(accountHint: accountHint);
      }

      return AuthResult.failure(_extractError(response));
    } catch (e, st) {
      return _handleException(e, st);
    }
  }

  Future<AuthResult> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      final url = _uri(AppConstants.resetPasswordEndpoint);
      final body = jsonEncode({'token': token, 'password': newPassword});

      final response = await http
          .post(url, headers: _jsonHeaders, body: body)
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        return const AuthResult.success();
      }

      return AuthResult.failure(_extractError(response));
    } catch (e, st) {
      return _handleException(e, st);
    }
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<String?> getToken() => _storage.read(key: AppConstants.tokenKey);
  Future<String?> getEmail() => _storage.read(key: AppConstants.emailKey);
  Future<String?> getUserId() => _storage.read(key: AppConstants.userIdKey);

  Future<DateTime?> getAccountCreatedAt() async {
    final raw = await _storage.read(key: AppConstants.accountCreatedAtKey);
    return _readIsoDate(raw);
  }

  Future<DateTime?> getLastLoginAt() async {
    final raw = await _storage.read(key: AppConstants.lastLoginAtKey);
    return _readIsoDate(raw);
  }

  Future<void> logout() async {
    await Future.wait([
      _storage.delete(key: AppConstants.tokenKey),
      _storage.delete(key: AppConstants.emailKey),
      _storage.delete(key: AppConstants.userIdKey),
      _storage.delete(key: AppConstants.accountCreatedAtKey),
      _storage.delete(key: AppConstants.lastLoginAtKey),
    ]);
  }

  Future<void> _persistSession({
    required String token,
    required String email,
    required String? userId,
    required DateTime? accountCreatedAt,
    required DateTime lastLoginAt,
  }) async {
    final operations = <Future<void>>[
      _storage.write(key: AppConstants.tokenKey, value: token),
      _storage.write(key: AppConstants.emailKey, value: email),
      _storage.write(
        key: AppConstants.lastLoginAtKey,
        value: lastLoginAt.toUtc().toIso8601String(),
      ),
    ];

    if (userId != null) {
      operations.add(
        _storage.write(key: AppConstants.userIdKey, value: userId),
      );
    } else {
      operations.add(_storage.delete(key: AppConstants.userIdKey));
    }

    if (accountCreatedAt != null) {
      operations.add(
        _storage.write(
          key: AppConstants.accountCreatedAtKey,
          value: accountCreatedAt.toUtc().toIso8601String(),
        ),
      );
    } else {
      operations.add(
        _storage.delete(key: AppConstants.accountCreatedAtKey),
      );
    }

    await Future.wait(operations);
  }
}
