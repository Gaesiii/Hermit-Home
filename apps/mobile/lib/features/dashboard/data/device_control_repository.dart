import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../domain/device_control_state.dart';

class DeviceControlRepository {
  DeviceControlRepository({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<DeviceControlSnapshot> fetchCurrentState({
    required String userId,
    required String token,
    int limit = 100,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.apiBaseUrl}/api/devices/$userId/control?limit=$limit',
    );

    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(AppConstants.requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(_extractError(response.body, response.statusCode));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected control response format.');
    }

    final historyRaw = decoded['history'];
    if (historyRaw is! List) {
      return const DeviceControlSnapshot(
        state: DeviceControlState.initial,
        historyCount: 0,
      );
    }

    DeviceControlState state = DeviceControlState.initial;
    DateTime? lastUpdatedAt;

    final history = historyRaw.whereType<Map<String, dynamic>>().toList();
    if (history.isNotEmpty) {
      final latest = history.first;
      lastUpdatedAt = _tryParseDateTime(latest['createdAt']);
    }

    for (final entry in history.reversed) {
      final patch = entry['state'];
      if (patch is Map<String, dynamic>) {
        state = state.applyPatch(patch);
      }
    }

    return DeviceControlSnapshot(
      state: state,
      historyCount: history.length,
      lastUpdatedAt: lastUpdatedAt,
    );
  }

  Future<DeviceControlApplyResult> setDeviceState({
    required String userId,
    required String token,
    required String deviceKey,
    required bool enabled,
  }) async {
    final uri =
        Uri.parse('${AppConstants.apiBaseUrl}/api/devices/$userId/control');
    final body = jsonEncode({deviceKey: enabled});

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: body,
        )
        .timeout(AppConstants.requestTimeout);

    if (response.statusCode != 200 && response.statusCode != 207) {
      throw Exception(_extractError(response.body, response.statusCode));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return DeviceControlApplyResult(
        appliedValue: enabled,
        mistLockedOff: false,
      );
    }

    bool appliedValue = enabled;
    final appliedState = decoded['appliedState'];
    if (appliedState is Map<String, dynamic>) {
      final raw = appliedState[deviceKey];
      if (raw is bool) {
        appliedValue = raw;
      }
    }

    final mistLockedOff = decoded['mist_locked_off'] == true;

    return DeviceControlApplyResult(
      appliedValue: appliedValue,
      mistLockedOff: mistLockedOff,
    );
  }

  DateTime? _tryParseDateTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  String _extractError(String body, int statusCode) {
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

    return 'Control request failed (HTTP $statusCode).';
  }
}
