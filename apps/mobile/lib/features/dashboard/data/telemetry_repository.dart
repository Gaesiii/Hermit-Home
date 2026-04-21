import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../domain/telemetry_model.dart';

class TelemetryRepository {
  TelemetryRepository({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<TelemetryModel>> fetchByUserId({
    required String userId,
    required String token,
    int limit = 30,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.apiBaseUrl}/api/devices/$userId/data?type=history&limit=$limit',
    );

    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(AppConstants.requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(_extractError(response.body, response.statusCode, uri));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected telemetry response format.');
    }

    final telemetryRaw = decoded['telemetry'];
    if (telemetryRaw is! List) {
      return const [];
    }

    return telemetryRaw
        .whereType<Map<String, dynamic>>()
        .map(TelemetryModel.fromJson)
        .toList(growable: false);
  }

  String _extractError(String body, int statusCode, Uri uri) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['error'] ?? decoded['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message;
        }
      }
    } catch (_) {
      // Ignore malformed JSON body and fallback to generic message.
    }

    final compactBody = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compactBody.isNotEmpty) {
      final preview = compactBody.length > 160
          ? '${compactBody.substring(0, 160)}...'
          : compactBody;
      return 'Telemetry request failed (HTTP $statusCode) at $uri: $preview';
    }

    return 'Telemetry request failed (HTTP $statusCode) at $uri.';
  }
}
