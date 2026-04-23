enum ChatboxRole {
  user,
  assistant,
}

class ChatboxMessage {
  const ChatboxMessage({
    required this.role,
    required this.content,
  });

  final ChatboxRole role;
  final String content;

  bool get isUser => role == ChatboxRole.user;

  Map<String, dynamic> toRequestJson() {
    return <String, dynamic>{
      'role': role == ChatboxRole.user ? 'user' : 'assistant',
      'content': content,
    };
  }

  Map<String, dynamic> toStorageJson() => toRequestJson();

  factory ChatboxMessage.fromStorageJson(Map<String, dynamic> json) {
    final roleRaw = json['role'];
    final role =
        roleRaw == 'assistant' ? ChatboxRole.assistant : ChatboxRole.user;
    final contentRaw = json['content'];
    final content = contentRaw is String ? contentRaw.trim() : '';
    return ChatboxMessage(
      role: role,
      content: content,
    );
  }

  factory ChatboxMessage.user(String content) {
    return ChatboxMessage(
      role: ChatboxRole.user,
      content: content,
    );
  }

  factory ChatboxMessage.assistant(String content) {
    return ChatboxMessage(
      role: ChatboxRole.assistant,
      content: content,
    );
  }
}

class ChatboxReply {
  const ChatboxReply({
    required this.answer,
    required this.suggestions,
    required this.mode,
    this.historyContext,
    this.context,
  });

  final String answer;
  final List<String> suggestions;
  final String mode;
  final Map<String, dynamic>? historyContext;
  final Map<String, dynamic>? context;

  bool get isContextResponse => mode == 'context';

  factory ChatboxReply.fromJson(Map<String, dynamic> json) {
    final answerRaw = json['answer'];
    final answer = answerRaw is String ? answerRaw.trim() : '';
    final modeRaw = json['mode'];
    final mode = modeRaw is String ? modeRaw.trim() : 'chat';

    final suggestionsRaw = json['suggestions'];
    final suggestions = suggestionsRaw is List
        ? suggestionsRaw
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false)
        : const <String>[];

    final historyContextRaw = json['historyContext'];
    final historyContext = historyContextRaw is Map
        ? historyContextRaw.cast<String, dynamic>()
        : null;

    final contextRaw = json['context'];
    final context =
        contextRaw is Map ? contextRaw.cast<String, dynamic>() : null;

    return ChatboxReply(
      answer: answer,
      suggestions: suggestions,
      mode: mode,
      historyContext: historyContext,
      context: context,
    );
  }
}
