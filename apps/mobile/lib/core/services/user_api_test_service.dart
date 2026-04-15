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
  final Map<String, String> responseHeaders;

  const ApiProbeResult({
    required this.method,
    required this.url,
    required this.requestBody,
    required this.statusCode,
    required this.responseBody,
    required this.errorMessage,
    required this.timestamp,
    required this.responseHeaders,
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

  Map<String, String> _headers({
    required bool withJsonBody,
    String? bearerToken,
    String? apiKey,
  }) {
    final headers = <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
    };

    if (withJsonBody) {
      headers[HttpHeaders.contentTypeHeader] = 'application/json';
    }

    if (bearerToken != null && bearerToken.trim().isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer ${bearerToken.trim()}';
    }

    if (apiKey != null && apiKey.trim().isNotEmpty) {
      headers['X-API-Key'] = apiKey.trim();
    }

    return headers;
  }

  Uri _buildUri(String baseUrl, String endpoint) {
    final normalizedBase = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final normalizedEndpoint = endpoint.trim().startsWith('/')
        ? endpoint.trim()
        : '/${endpoint.trim()}';
    return Uri.parse('$normalizedBase$normalizedEndpoint');
  }

  Future<ApiProbeResult> request({
    required String baseUrl,
    required String method,
    required String endpoint,
    Map<String, dynamic>? jsonBody,
    String? bearerToken,
    String? apiKey,
  }) async {
    final upperMethod = method.toUpperCase().trim();
    final uri = _buildUri(baseUrl, endpoint);
    final hasBody = jsonBody != null;
    final requestBody = hasBody ? jsonEncode(jsonBody) : '';
    final timestamp = DateTime.now();

    try {
      final response = await _sendHttp(
        method: upperMethod,
        uri: uri,
        headers: _headers(
          withJsonBody: hasBody,
          bearerToken: bearerToken,
          apiKey: apiKey,
        ),
        body: hasBody ? requestBody : null,
      ).timeout(AppConstants.requestTimeout);

      return ApiProbeResult(
        method: upperMethod,
        url: uri.toString(),
        requestBody: requestBody,
        statusCode: response.statusCode,
        responseBody: response.body,
        errorMessage: null,
        timestamp: timestamp,
        responseHeaders: response.headers,
      );
    } on TimeoutException {
      return ApiProbeResult(
        method: upperMethod,
        url: uri.toString(),
        requestBody: requestBody,
        statusCode: null,
        responseBody: '',
        errorMessage: 'Request timed out.',
        timestamp: timestamp,
        responseHeaders: const {},
      );
    } on SocketException catch (error) {
      return ApiProbeResult(
        method: upperMethod,
        url: uri.toString(),
        requestBody: requestBody,
        statusCode: null,
        responseBody: '',
        errorMessage: 'Network error: $error',
        timestamp: timestamp,
        responseHeaders: const {},
      );
    } on FormatException catch (error) {
      return ApiProbeResult(
        method: upperMethod,
        url: uri.toString(),
        requestBody: requestBody,
        statusCode: null,
        responseBody: '',
        errorMessage: 'Invalid response format: $error',
        timestamp: timestamp,
        responseHeaders: const {},
      );
    } catch (error) {
      return ApiProbeResult(
        method: upperMethod,
        url: uri.toString(),
        requestBody: requestBody,
        statusCode: null,
        responseBody: '',
        errorMessage: 'Unexpected error: $error',
        timestamp: timestamp,
        responseHeaders: const {},
      );
    }
  }

  Future<http.Response> _sendHttp({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String? body,
  }) {
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(uri, headers: headers, body: body);
      case 'PATCH':
        return _client.patch(uri, headers: headers, body: body);
      case 'PUT':
        return _client.put(uri, headers: headers, body: body);
      case 'DELETE':
        return _client.delete(uri, headers: headers, body: body);
      case 'OPTIONS':
        return _client
            .send(http.Request('OPTIONS', uri)..headers.addAll(headers))
            .then(
              (streamed) => http.Response.fromStream(streamed),
            );
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }
  }

  Future<ApiProbeResult> register({
    required String baseUrl,
    required String email,
    required String password,
  }) {
    return request(
      baseUrl: baseUrl,
      method: 'POST',
      endpoint: AppConstants.registerEndpoint,
      jsonBody: {'email': email.trim(), 'password': password},
    );
  }

  Future<ApiProbeResult> login({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    final result = await request(
      baseUrl: baseUrl,
      method: 'POST',
      endpoint: AppConstants.loginEndpoint,
      jsonBody: {'email': email.trim(), 'password': password},
    );

    if (result.success) {
      await _saveSessionFromLoginResponse(result.responseBody);
    }

    return result;
  }

  Future<ApiProbeResult> getDevices({
    required String baseUrl,
  }) {
    return request(
      baseUrl: baseUrl,
      method: 'GET',
      endpoint: AppConstants.devicesEndpoint,
    );
  }

  Future<ApiProbeResult> getDeviceById({
    required String baseUrl,
    required String deviceId,
    String? bearerToken,
    String? apiKey,
  }) {
    return request(
      baseUrl: baseUrl,
      method: 'GET',
      endpoint: AppConstants.deviceByIdEndpoint(deviceId),
      bearerToken: bearerToken,
      apiKey: apiKey,
    );
  }

  Future<ApiProbeResult> patchDeviceById({
    required String baseUrl,
    required String deviceId,
    required Map<String, dynamic> patch,
    String? bearerToken,
    String? apiKey,
  }) {
    return request(
      baseUrl: baseUrl,
      method: 'PATCH',
      endpoint: AppConstants.deviceByIdEndpoint(deviceId),
      jsonBody: patch,
      bearerToken: bearerToken,
      apiKey: apiKey,
    );
  }

  Future<ApiProbeResult> getDeviceStatus({
    required String baseUrl,
    required String deviceId,
    String? bearerToken,
    String? apiKey,
  }) {
    return request(
      baseUrl: baseUrl,
      method: 'GET',
      endpoint: AppConstants.deviceStatusEndpoint(deviceId),
      bearerToken: bearerToken,
      apiKey: apiKey,
    );
  }

  Future<ApiProbeResult> sendOverride({
    required String baseUrl,
    required String deviceId,
    required Map<String, dynamic> payload,
    String? bearerToken,
    String? apiKey,
  }) {
    return request(
      baseUrl: baseUrl,
      method: 'POST',
      endpoint: AppConstants.deviceOverrideEndpoint(deviceId),
      jsonBody: payload,
      bearerToken: bearerToken,
      apiKey: apiKey,
    );
  }

  Future<ApiProbeResult> getControlHistory({
    required String baseUrl,
    required String deviceId,
    int? limit,
    String? bearerToken,
    String? apiKey,
  }) {
    final endpoint = limit != null
        ? '${AppConstants.deviceControlEndpoint(deviceId)}?limit=$limit'
        : AppConstants.deviceControlEndpoint(deviceId);

    return request(
      baseUrl: baseUrl,
      method: 'GET',
      endpoint: endpoint,
      bearerToken: bearerToken,
      apiKey: apiKey,
    );
  }

  Future<ApiProbeResult> postControlUpdate({
    required String baseUrl,
    required String deviceId,
    required Map<String, dynamic> payload,
    String? bearerToken,
    String? apiKey,
  }) {
    return request(
      baseUrl: baseUrl,
      method: 'POST',
      endpoint: AppConstants.deviceControlEndpoint(deviceId),
      jsonBody: payload,
      bearerToken: bearerToken,
      apiKey: apiKey,
    );
  }

  Future<ApiProbeResult> getSchedules({
    required String baseUrl,
    String? bearerToken,
    String? apiKey,
  }) {
    return request(
      baseUrl: baseUrl,
      method: 'GET',
      endpoint: AppConstants.deviceSchedulesEndpoint,
      bearerToken: bearerToken,
      apiKey: apiKey,
    );
  }

  Future<ApiProbeResult> options({
    required String baseUrl,
    required String endpoint,
    String? bearerToken,
    String? apiKey,
  }) {
    return request(
      baseUrl: baseUrl,
      method: 'OPTIONS',
      endpoint: endpoint,
      bearerToken: bearerToken,
      apiKey: apiKey,
    );
  }

  String? extractUserIdFromJwt(String? token) {
    if (token == null || token.trim().isEmpty) {
      return null;
    }

    final parts = token.split('.');
    if (parts.length < 2) {
      return null;
    }

    try {
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final userId = decoded['userId'];
      if (userId is String && userId.trim().isNotEmpty) {
        return userId.trim();
      }
    } catch (_) {
      return null;
    }

    return null;
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
