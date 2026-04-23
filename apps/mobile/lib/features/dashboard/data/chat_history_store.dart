import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/chatbox_models.dart';

class ChatHistoryStore {
  static const String _keyPrefix = 'hh_chat_history_';
  static const int _maxMessages = 80;

  Future<List<ChatboxMessage>> readHistory(String userId) async {
    final key = _keyForUser(userId);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) {
      return const <ChatboxMessage>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <ChatboxMessage>[];
      }

      final messages = decoded
          .whereType<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .map(ChatboxMessage.fromStorageJson)
          .where((entry) => entry.content.isNotEmpty)
          .toList(growable: false);

      if (messages.length <= _maxMessages) {
        return messages;
      }
      return messages.sublist(messages.length - _maxMessages);
    } catch (_) {
      return const <ChatboxMessage>[];
    }
  }

  Future<void> writeHistory(
      String userId, List<ChatboxMessage> messages) async {
    final key = _keyForUser(userId);
    final prefs = await SharedPreferences.getInstance();

    final normalized = messages
        .where((entry) => entry.content.trim().isNotEmpty)
        .toList(growable: false);
    final trimmed = normalized.length <= _maxMessages
        ? normalized
        : normalized.sublist(normalized.length - _maxMessages);

    final payload =
        trimmed.map((entry) => entry.toStorageJson()).toList(growable: false);
    await prefs.setString(key, jsonEncode(payload));
  }

  Future<void> clearHistory(String userId) async {
    final key = _keyForUser(userId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  String _keyForUser(String userId) => '$_keyPrefix$userId';
}
