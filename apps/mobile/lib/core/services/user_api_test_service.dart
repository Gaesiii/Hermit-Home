import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';

class ApiProbeResult {
  final String method;
  final String url;
  final String requestBody;
  final int? statusCode;
  final String responseBody;
  final String? errorMessage;
  final DateTime timestamp;

  const ApiProbeResult({
    required this.method,
    required this.url,
    required this.requestBody,
    required this.statusCode,
    required this.responseBody,
    required this.errorMessage,
    required this.timestamp,
  });

  bool get success =>
      statusCode != null && statusCode! >= 200 && statusCode! < 300;
}

class SessionSnapshot {
  final String? token;
  final String? email;

  const SessionSnapshot({required this.token, required this.email});
}

class UserApiTestService {
  UserApiTestService({
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final http.Client _client;
  final FlutterSecureStorage _storage;

  Map<String, String> get _jsonHeaders => {
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.acceptHeader: 'application/json',
      };

  Uri _buildUri(String baseUrl, String endpoint) {
    final normalizedBase = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalizedBase$endpoint');
  }

  Future<ApiProbeResult> register({
    required String baseUrl,
    required String email,
    required String password,
  }) {
    final body = <String, dynamic>{
      'email': email.trim(),
      'password': password,
    };

    return _postJson(
      method: 'POST',
      uri: _buildUri(baseUrl, AppConstants.registerEndpoint),
      body: body,
    );
  }

  Future<ApiProbeResult> login({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    final body = <String, dynamic>{
      'email': email.trim(),
      'password': password,
    };

    final result = await _postJson(
      method: 'POST',
      uri: _buildUri(baseUrl, AppConstants.loginEndpoint),
      body: body,
    );

    if (result.success) {
      await _saveSessionFromLoginResponse(result.responseBody);
    }

    return result;
  }

  Future<ApiProbeResult> _postJson({
    required String method,
    required Uri uri,
    required Map<String, dynamic> body,
  }) async {
    final requestBody = jsonEncode(body);
    final timestamp = DateTime.now();

    try {
      final response = await _client
          .post(
            uri,
            headers: _jsonHeaders,
            body: requestBody,
          )
          .timeout(AppConstants.requestTimeout);

      return ApiProbeResult(
        method: method,
        url: uri.toString(),
        requestBody: requestBody,
        statusCode: response.statusCode,
        responseBody: response.body,
        errorMessage: null,
        timestamp: timestamp,
      );
    } on TimeoutException {
      return ApiProbeResult(
        method: method,
        url: uri.toString(),
        requestBody: requestBody,
        statusCode: null,
        responseBody: '',
        errorMessage: 'Request timed out.',
        timestamp: timestamp,
      );
    } on SocketException catch (error) {
      return ApiProbeResult(
        method: method,
        url: uri.toString(),
        requestBody: requestBody,
        statusCode: null,
        responseBody: '',
        errorMessage: 'Network error: $error',
        timestamp: timestamp,
      );
    } on FormatException catch (error) {
      return ApiProbeResult(
        method: method,
        url: uri.toString(),
        requestBody: requestBody,
        statusCode: null,
        responseBody: '',
        errorMessage: 'Invalid response format: $error',
        timestamp: timestamp,
      );
    } catch (error) {
      return ApiProbeResult(
        method: method,
        url: uri.toString(),
        requestBody: requestBody,
        statusCode: null,
        responseBody: '',
        errorMessage: 'Unexpected error: $error',
        timestamp: timestamp,
      );
    }
  }

  Future<void> _saveSessionFromLoginResponse(String responseBody) async {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final token = decoded['token'];
      if (token is! String || token.isEmpty) {
        return;
      }

      String? email;
      String? userId;
      String? createdAt;
      final user = decoded['user'];
      if (user is Map<String, dynamic>) {
        final userEmail = user['email'];
        if (userEmail is String && userEmail.isNotEmpty) {
          email = userEmail;
        }

        final idValue = user['_id'];
        if (idValue is String && idValue.isNotEmpty) {
          userId = idValue;
        }

        final createdAtValue = user['createdAt'];
        if (createdAtValue is String && createdAtValue.isNotEmpty) {
          createdAt = createdAtValue;
        }
      }

      final operations = <Future<void>>[
        _storage.write(key: AppConstants.tokenKey, value: token),
        _storage.write(
          key: AppConstants.lastLoginAtKey,
          value: DateTime.now().toUtc().toIso8601String(),
        ),
      ];

      if (email != null) {
        operations
            .add(_storage.write(key: AppConstants.emailKey, value: email));
      } else {
        operations.add(_storage.delete(key: AppConstants.emailKey));
      }

      if (userId != null) {
        operations
            .add(_storage.write(key: AppConstants.userIdKey, value: userId));
      } else {
        operations.add(_storage.delete(key: AppConstants.userIdKey));
      }

      if (createdAt != null) {
        operations.add(
          _storage.write(
              key: AppConstants.accountCreatedAtKey, value: createdAt),
        );
      } else {
        operations.add(_storage.delete(key: AppConstants.accountCreatedAtKey));
      }

      await Future.wait(operations);
    } catch (_) {
      return;
    }
  }

  Future<void> clearSession() async {
    await Future.wait([
      _storage.delete(key: AppConstants.tokenKey),
      _storage.delete(key: AppConstants.emailKey),
      _storage.delete(key: AppConstants.userIdKey),
      _storage.delete(key: AppConstants.accountCreatedAtKey),
      _storage.delete(key: AppConstants.lastLoginAtKey),
    ]);
  }

  Future<SessionSnapshot> readSession() async {
    final token = await _storage.read(key: AppConstants.tokenKey);
    final email = await _storage.read(key: AppConstants.emailKey);
    return SessionSnapshot(token: token, email: email);
  }
}
