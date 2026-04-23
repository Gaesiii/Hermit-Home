import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../domain/chatbox_models.dart';

class ChatboxRepository {
  ChatboxRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<ChatboxReply> fetchSuggestions({
    required String userId,
    required String token,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.apiBaseUrl}${AppConstants.deviceChatboxEndpoint(userId)}',
    );

    final response = await _client.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(AppConstants.requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(_extractError(response.body, response.statusCode));
    }

    return _parseReply(response.body);
  }

  Future<ChatboxReply> sendMessage({
    required String userId,
    required String token,
    required String message,
    required List<ChatboxMessage> history,
    bool requestContext = false,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.apiBaseUrl}${AppConstants.deviceChatboxEndpoint(userId)}',
    );

    final response = await _client
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(<String, dynamic>{
            'message': message,
            'history': history
                .map((entry) => entry.toRequestJson())
                .toList(growable: false),
            'mode': requestContext ? 'context' : 'chat',
            'requestContext': requestContext,
          }),
        )
        .timeout(AppConstants.requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(_extractError(response.body, response.statusCode));
    }

    return _parseReply(response.body);
  }

  ChatboxReply _parseReply(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected chatbox response format.');
    }

    return ChatboxReply.fromJson(decoded);
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

    return 'Chatbox request failed (HTTP $statusCode).';
  }
}
