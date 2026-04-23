import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_routes.dart';
import 'data/chat_history_store.dart';
import 'data/chatbox_repository.dart';
import 'data/device_control_repository.dart';
import 'data/telemetry_repository.dart';
import 'domain/chatbox_models.dart';
import 'domain/device_control_state.dart';
import 'domain/telemetry_model.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService _authService = AuthService();
  final TelemetryRepository _telemetryRepository = TelemetryRepository();
  final DeviceControlRepository _deviceControlRepository =
      DeviceControlRepository();
  final ChatHistoryStore _chatHistoryStore = ChatHistoryStore();
  final ChatboxRepository _chatboxRepository = ChatboxRepository();
  final TextEditingController _chatboxController = TextEditingController();
  final ScrollController _chatboxScrollController = ScrollController();

  bool _isLoading = true;

  String? _email;
  String? _token;
  String? _userId;
  DateTime? _accountCreatedAt;
  DateTime? _lastLoginAt;
  _JwtSessionInfo _jwtInfo = const _JwtSessionInfo();

  List<TelemetryModel> _telemetry = const [];
  String? _telemetryError;

  DeviceControlState _deviceState = DeviceControlState.initial;
  DateTime? _deviceStateUpdatedAt;
  int _deviceStateHistoryCount = 0;
  String? _deviceStateError;
  final Set<String> _pendingControlKeys = <String>{};

  List<ChatboxMessage> _chatMessages = const [];
  List<String> _chatSuggestions = const [];
  String _chatboxDraft = '';
  bool _isLoadingChatboxSuggestions = false;
  bool _isSendingChatMessage = false;
  DateTime? _chatboxUpdatedAt;
  String? _chatboxError;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _chatboxController.dispose();
    _chatboxScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSession() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    final values = await Future.wait<Object?>([
      _authService.getEmail(),
      _authService.getToken(),
      _authService.getUserId(),
      _authService.getAccountCreatedAt(),
      _authService.getLastLoginAt(),
    ]);

    if (!mounted) return;

    final email = values[0] as String?;
    final token = values[1] as String?;
    final storedUserId = values[2] as String?;
    final accountCreatedAt = values[3] as DateTime?;
    final lastLoginAt = values[4] as DateTime?;

    final sessionInfo = _JwtSessionInfo.fromToken(token);
    final resolvedUserId = storedUserId ?? sessionInfo.userId;

    List<TelemetryModel> telemetry = const [];
    String? telemetryError;

    DeviceControlSnapshot controlSnapshot = const DeviceControlSnapshot(
      state: DeviceControlState.initial,
      historyCount: 0,
    );
    String? controlError;
    ChatboxReply? chatboxReply;
    String? chatboxError;
    List<ChatboxMessage> persistedChatMessages = const <ChatboxMessage>[];

    if (resolvedUserId != null && resolvedUserId.isNotEmpty) {
      persistedChatMessages = await _chatHistoryStore.readHistory(resolvedUserId);
    }

    if (resolvedUserId == null || resolvedUserId.isEmpty) {
      telemetryError = 'Cannot find userId in current session.';
      controlError = 'Cannot find userId in current session.';
      chatboxError = 'Cannot find userId in current session.';
    } else if (token == null || token.isEmpty) {
      telemetryError = 'Cannot find valid access token.';
      controlError = 'Cannot find valid access token.';
      chatboxError = 'Cannot find valid access token.';
    } else {
      await Future.wait<void>([
        () async {
          try {
            telemetry = await _telemetryRepository.fetchByUserId(
              userId: resolvedUserId,
              token: token,
              limit: 40,
            );
          } catch (error) {
            telemetryError = error.toString().replaceFirst('Exception: ', '');
          }
        }(),
        () async {
          try {
            controlSnapshot = await _deviceControlRepository.fetchCurrentState(
              userId: resolvedUserId,
              token: token,
              limit: 100,
            );
          } catch (error) {
            controlError = error.toString().replaceFirst('Exception: ', '');
          }
        }(),
        () async {
          try {
            chatboxReply = await _chatboxRepository.fetchSuggestions(
              userId: resolvedUserId,
              token: token,
            );
          } catch (error) {
            chatboxError = error.toString().replaceFirst('Exception: ', '');
          }
        }(),
      ]);
    }

    if (!mounted) return;

    final shouldResetChat = _userId != null && _userId != resolvedUserId;
    var seededAssistantFromSuggestions = false;

    setState(() {
      _email = email;
      _token = token;
      _userId = resolvedUserId;
      _accountCreatedAt = accountCreatedAt;
      _lastLoginAt = lastLoginAt;
      _jwtInfo = sessionInfo;

      _telemetry = telemetry;
      _telemetryError = telemetryError;

      _deviceState = controlSnapshot.state;
      _deviceStateUpdatedAt = controlSnapshot.lastUpdatedAt;
      _deviceStateHistoryCount = controlSnapshot.historyCount;
      _deviceStateError = controlError;
      _pendingControlKeys.clear();

      if (shouldResetChat) {
        _chatSuggestions = const [];
        _chatboxDraft = '';
        _chatboxController.clear();
        _isLoadingChatboxSuggestions = false;
        _isSendingChatMessage = false;
        _chatboxUpdatedAt = null;
        _chatboxError = null;
      }

      final shouldHydrateChat = shouldResetChat || _chatMessages.isEmpty;
      if (shouldHydrateChat) {
        _chatMessages = persistedChatMessages;
      }

      if (chatboxReply != null) {
        _chatSuggestions = chatboxReply!.suggestions;
        _chatboxUpdatedAt = DateTime.now();
        _chatboxError = null;

        final answer = chatboxReply!.answer.trim();
        if (_chatMessages.isEmpty && answer.isNotEmpty) {
          _chatMessages = <ChatboxMessage>[ChatboxMessage.assistant(answer)];
          seededAssistantFromSuggestions = true;
        }
      } else if (chatboxError != null) {
        _chatboxError = chatboxError;
      }
      _isLoadingChatboxSuggestions = false;

      _isLoading = false;
    });

    if (seededAssistantFromSuggestions) {
      await _persistChatHistory();
    }

    if ((chatboxReply != null || persistedChatMessages.isNotEmpty) &&
        _chatMessages.isNotEmpty) {
      _queueChatScrollToBottom();
    }
  }

  Future<void> _toggleDevice(String deviceKey, bool enabled) async {
    final userId = _userId;
    final token = _token;

    if (userId == null || userId.isEmpty || token == null || token.isEmpty) {
      _showSnack('Session is missing userId or token. Please sign in again.');
      return;
    }

    if (_pendingControlKeys.contains(deviceKey)) {
      return;
    }

    final previousValue = _deviceState.valueForKey(deviceKey);

    setState(() {
      _pendingControlKeys.add(deviceKey);
      _deviceState = _deviceState.withKey(deviceKey, enabled);
    });

    try {
      final result = await _deviceControlRepository.setDeviceState(
        userId: userId,
        token: token,
        deviceKey: deviceKey,
        enabled: enabled,
      );

      if (!mounted) return;

      setState(() {
        _deviceState = _deviceState.withKey(deviceKey, result.appliedValue);
        _deviceStateUpdatedAt = DateTime.now();
        _pendingControlKeys.remove(deviceKey);
        _deviceStateError = null;
      });

      if (result.mistLockedOff) {
        _showSnack('Mist safety lock is active. Mist remains OFF.');
      }
    } catch (error) {
      if (!mounted) return;

      final errorMessage = error.toString().replaceFirst('Exception: ', '');

      setState(() {
        _deviceState = _deviceState.withKey(deviceKey, previousValue);
        _pendingControlKeys.remove(deviceKey);
        _deviceStateError = errorMessage;
      });

      _showSnack(errorMessage);
    }
  }

  Future<void> _refreshChatboxSuggestions() async {
    final userId = _userId;
    final token = _token;

    if (userId == null || userId.isEmpty || token == null || token.isEmpty) {
      _showSnack('Session is missing userId or token. Please sign in again.');
      return;
    }

    if (_isLoadingChatboxSuggestions || _isSendingChatMessage) {
      return;
    }

    setState(() {
      _isLoadingChatboxSuggestions = true;
      _chatboxError = null;
    });

    try {
      final reply = await _chatboxRepository.fetchSuggestions(
        userId: userId,
        token: token,
      );

      if (!mounted) return;
      var seededAssistant = false;

      setState(() {
        _chatSuggestions = reply.suggestions;
        _chatboxUpdatedAt = DateTime.now();
        _chatboxError = null;
        _isLoadingChatboxSuggestions = false;

        final answer = reply.answer.trim();
        if (_chatMessages.isEmpty && answer.isNotEmpty) {
          _chatMessages = <ChatboxMessage>[ChatboxMessage.assistant(answer)];
          seededAssistant = true;
        }
      });

      if (seededAssistant) {
        await _persistChatHistory();
      }

      _queueChatScrollToBottom();
    } catch (error) {
      if (!mounted) return;

      final errorMessage = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _chatboxError = errorMessage;
        _isLoadingChatboxSuggestions = false;
      });

      _showSnack(errorMessage);
    }
  }

  Future<void> _sendChatMessage([String? preset]) async {
    final userId = _userId;
    final token = _token;

    if (userId == null || userId.isEmpty || token == null || token.isEmpty) {
      _showSnack('Session is missing userId or token. Please sign in again.');
      return;
    }

    if (_isSendingChatMessage) {
      return;
    }

    final message = (preset ?? _chatboxController.text).trim();
    if (message.isEmpty) {
      return;
    }

    final historyBeforeSend = List<ChatboxMessage>.from(_chatMessages);
    final requestContext = _isContextRequest(message);

    setState(() {
      _chatMessages = <ChatboxMessage>[
        ..._chatMessages,
        ChatboxMessage.user(message),
      ];
      _chatboxController.clear();
      _chatboxDraft = '';
      _chatboxError = null;
      _isSendingChatMessage = true;
    });

    await _persistChatHistory();
    _queueChatScrollToBottom();

    try {
      final reply = await _chatboxRepository.sendMessage(
        userId: userId,
        token: token,
        message: message,
        history: historyBeforeSend,
        requestContext: requestContext,
      );

      if (!mounted) return;

      setState(() {
        final answer = reply.answer.trim();
        if (answer.isNotEmpty) {
          _chatMessages = <ChatboxMessage>[
            ..._chatMessages,
            ChatboxMessage.assistant(answer),
          ];
        }

        _chatSuggestions = reply.suggestions;
        _chatboxUpdatedAt = DateTime.now();
        _chatboxError = null;
        _isSendingChatMessage = false;
      });

      await _persistChatHistory();
      _queueChatScrollToBottom();
    } catch (error) {
      if (!mounted) return;

      final errorMessage = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _chatboxError = errorMessage;
        _isSendingChatMessage = false;
      });

      _showSnack(errorMessage);
    }
  }

  bool _isContextRequest(String message) {
    final normalized =
        message.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    const triggers = <String>[
      'l\u1ea5y ng\u1eef c\u1ea3nh',
      'lay ngu canh',
      'ng\u1eef c\u1ea3nh',
      'ngu canh',
      'l\u1ea5y b\u1ed1i c\u1ea3nh',
      'lay boi canh',
      'context',
      'context snapshot',
      'summary context',
      'tom tat ngu canh',
      't\u00f3m t\u1eaft ng\u1eef c\u1ea3nh',
      'context tong hop',
    ];
    return triggers.any(normalized.contains);
  }

  Future<void> _persistChatHistory() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      return;
    }

    try {
      await _chatHistoryStore.writeHistory(userId, _chatMessages);
    } catch (_) {
      // Ignore local persistence errors to avoid blocking the chat flow.
    }
  }

  Future<void> _clearChatHistory() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      return;
    }

    setState(() {
      _chatMessages = const <ChatboxMessage>[];
    });

    try {
      await _chatHistoryStore.clearHistory(userId);
    } catch (_) {
      // Ignore local persistence errors to keep UI responsive.
    }
  }

  void _queueChatScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!_chatboxScrollController.hasClients) {
        return;
      }

      final maxExtent = _chatboxScrollController.position.maxScrollExtent;
      _chatboxScrollController.animateTo(
        maxExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.error,
        ),
      );
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;

    Navigator.of(context)
        .pushNamedAndRemoveUntil(AuthRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadSession,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh data',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSession,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildWelcomeCard(),
                  const SizedBox(height: 14),
                  _buildProfileCard(),
                  const SizedBox(height: 14),
                  _buildDeviceControlsCard(),
                  const SizedBox(height: 14),
                  _buildTelemetryCard(),
                  const SizedBox(height: 14),
                  _buildChatboxCard(),
                  const SizedBox(height: 14),
                  _buildSessionCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildWelcomeCard() {
    final sessionLabel = _jwtInfo.expiresAt == null
        ? 'Unknown'
        : _jwtInfo.isExpired
            ? 'Expired'
            : 'Active';

    final badgeColor = _jwtInfo.expiresAt == null
        ? Colors.grey
        : _jwtInfo.isExpired
            ? AppTheme.error
            : AppTheme.primary;

    return Container(
      decoration: AppTheme.cardDecoration(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome back',
                  style: TextStyle(fontSize: 13, color: AppTheme.subtle),
                ),
                const SizedBox(height: 4),
                Text(
                  _email ?? 'No email found',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: badgeColor.withValues(alpha: 0.45)),
            ),
            child: Text(
              sessionLabel,
              style: TextStyle(
                color: badgeColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      decoration: AppTheme.cardDecoration(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'User Info',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.mail_outline_rounded,
            label: 'Email',
            value: _email ?? 'Not available',
          ),
          _InfoRow(
            icon: Icons.badge_outlined,
            label: 'User ID',
            value: _userId ?? 'Not available',
          ),
          _InfoRow(
            icon: Icons.calendar_month_outlined,
            label: 'Account created',
            value: _formatDateTime(_accountCreatedAt),
          ),
          _InfoRow(
            icon: Icons.login_rounded,
            label: 'Last sign in',
            value: _formatDateTime(_lastLoginAt),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceControlsCard() {
    return Container(
      decoration: AppTheme.cardDecoration(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Device Controls',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF2A3530)),
                ),
                child: Text(
                  '$_deviceStateHistoryCount events',
                  style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Last sync: ${_formatDateTime(_deviceStateUpdatedAt)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
          ),
          if (_deviceStateError != null) ...[
            const SizedBox(height: 8),
            Text(
              _deviceStateError!,
              style: const TextStyle(color: AppTheme.error, height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          _DeviceControlTile(
            label: 'Den',
            subtitle: 'Light relay',
            icon: Icons.lightbulb_outline_rounded,
            value: _deviceState.light,
            isBusy: _pendingControlKeys.contains('light'),
            onChanged: (value) => _toggleDevice('light', value),
          ),
          const SizedBox(height: 10),
          _DeviceControlTile(
            label: 'Quat',
            subtitle: 'Fan relay',
            icon: Icons.air_rounded,
            value: _deviceState.fan,
            isBusy: _pendingControlKeys.contains('fan'),
            onChanged: (value) => _toggleDevice('fan', value),
          ),
          const SizedBox(height: 10),
          _DeviceControlTile(
            label: 'Phun suong',
            subtitle: 'Mist relay',
            icon: Icons.water_drop_outlined,
            value: _deviceState.mist,
            isBusy: _pendingControlKeys.contains('mist'),
            onChanged: (value) => _toggleDevice('mist', value),
          ),
          const SizedBox(height: 10),
          _DeviceControlTile(
            label: 'Suoi',
            subtitle: 'Heater relay',
            icon: Icons.local_fire_department_outlined,
            value: _deviceState.heater,
            isBusy: _pendingControlKeys.contains('heater'),
            onChanged: (value) => _toggleDevice('heater', value),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryCard() {
    return Container(
      decoration: AppTheme.cardDecoration(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Telemetry',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF2A3530)),
                ),
                child: Text(
                  '${_telemetry.length} records',
                  style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_telemetryError != null) ...[
            Text(
              _telemetryError!,
              style: const TextStyle(color: AppTheme.error, height: 1.4),
            ),
          ] else if (_telemetry.isEmpty) ...[
            const Text(
              'No telemetry records for this userId yet.',
              style: TextStyle(color: AppTheme.subtle),
            ),
          ] else ...[
            for (var i = 0; i < _telemetry.length; i++)
              _TelemetryTile(
                telemetry: _telemetry[i],
                isLast: i == _telemetry.length - 1,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildChatboxCard() {
    final isBusy = _isLoadingChatboxSuggestions || _isSendingChatMessage;
    final canSend = _chatboxDraft.trim().isNotEmpty && !_isSendingChatMessage;

    return Container(
      decoration: AppTheme.cardDecoration(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'AI Chatbox',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF2A3530)),
                ),
                child: Text(
                  '${_chatSuggestions.length} tips',
                  style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: isBusy ? null : _refreshChatboxSuggestions,
                icon: _isLoadingChatboxSuggestions
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh suggestions',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _chatboxUpdatedAt == null
                ? 'No chat sync yet.'
                : 'Last sync: ${_formatDateTime(_chatboxUpdatedAt)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
          ),
          if (_chatboxError != null) ...[
            const SizedBox(height: 8),
            Text(
              _chatboxError!,
              style: const TextStyle(color: AppTheme.error, height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                backgroundColor: AppTheme.surfaceVariant,
                side: const BorderSide(color: Color(0xFF2A3530)),
                label: const Text(
                  'Lay ngu canh',
                  style: TextStyle(fontSize: 12, color: AppTheme.onSurface),
                ),
                onPressed: isBusy
                    ? null
                    : () => _sendChatMessage(
                          'Lay ngu canh hien tai tu telemetry va lich su chat',
                        ),
              ),
              ActionChip(
                backgroundColor: AppTheme.surfaceVariant,
                side: const BorderSide(color: Color(0xFF2A3530)),
                label: const Text(
                  'Xoa lich su',
                  style: TextStyle(fontSize: 12, color: AppTheme.onSurface),
                ),
                onPressed: isBusy || _chatMessages.isEmpty
                    ? null
                    : _clearChatHistory,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 240,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A3530)),
            ),
            child: _chatMessages.isEmpty
                ? Center(
                    child: Text(
                      _isLoadingChatboxSuggestions
                          ? 'Loading chat suggestions...'
                          : 'Ask AI about current habitat conditions.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.subtle,
                        height: 1.4,
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _chatboxScrollController,
                    itemCount: _chatMessages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _ChatBubble(message: _chatMessages[index]);
                    },
                  ),
          ),
          const SizedBox(height: 10),
          if (_chatSuggestions.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tip in _chatSuggestions)
                  ActionChip(
                    backgroundColor: AppTheme.surfaceVariant,
                    side: const BorderSide(color: Color(0xFF2A3530)),
                    label: Text(
                      tip.length > 72 ? '${tip.substring(0, 72)}...' : tip,
                      style:
                          const TextStyle(fontSize: 12, color: AppTheme.onSurface),
                    ),
                    onPressed: _isSendingChatMessage
                        ? null
                        : () => _sendChatMessage(tip),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _chatboxController,
                  minLines: 1,
                  maxLines: 3,
                  enabled: !_isSendingChatMessage,
                  textInputAction: TextInputAction.send,
                  onChanged: (value) {
                    setState(() => _chatboxDraft = value);
                  },
                  onSubmitted: (_) => _sendChatMessage(),
                  decoration: const InputDecoration(
                    hintText: 'Ask AI about temperature, humidity, or relay actions',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: canSend ? _sendChatMessage : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(52, 52),
                  padding: EdgeInsets.zero,
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSendingChatMessage
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard() {
    return Container(
      decoration: AppTheme.cardDecoration(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Session Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.vpn_key_outlined,
            label: 'Token preview',
            value: _tokenPreview(_token),
          ),
          _InfoRow(
            icon: Icons.schedule_rounded,
            label: 'Issued at',
            value: _formatDateTime(_jwtInfo.issuedAt),
          ),
          _InfoRow(
            icon: Icons.event_busy_outlined,
            label: 'Expires at',
            value: _formatDateTime(_jwtInfo.expiresAt),
          ),
          const _InfoRow(
            icon: Icons.link_rounded,
            label: 'API endpoint',
            value: AppConstants.apiBaseUrl,
            isLast: true,
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Not available';

    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }

  String _tokenPreview(String? token) {
    if (token == null || token.isEmpty) {
      return 'Not available';
    }

    if (token.length <= 24) {
      return token;
    }

    final head = token.substring(0, 12);
    final tail = token.substring(token.length - 10);
    return '$head...$tail';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A3530)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppTheme.subtle),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style:
                        const TextStyle(fontSize: 12, color: AppTheme.subtle),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 14, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceControlTile extends StatelessWidget {
  const _DeviceControlTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.isBusy,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool value;
  final bool isBusy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3530)),
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? AppTheme.primary : AppTheme.subtle),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
                ),
              ],
            ),
          ),
          if (isBusy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppTheme.primary,
            ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
  });

  final ChatboxMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor =
        isUser ? AppTheme.primary.withValues(alpha: 0.18) : AppTheme.surface;
    final borderColor = isUser
        ? AppTheme.primary.withValues(alpha: 0.45)
        : const Color(0xFF2A3530);

    return Align(
      alignment: align,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          message.content,
          style: const TextStyle(height: 1.35),
        ),
      ),
    );
  }
}

class _TelemetryTile extends StatelessWidget {
  const _TelemetryTile({
    required this.telemetry,
    required this.isLast,
  });

  final TelemetryModel telemetry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3530)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatTimestamp(telemetry.timestamp),
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.subtle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ValueChip(
                label: 'Nhiet do',
                value: _formatNumber(telemetry.temperature, suffix: ' degC'),
              ),
              _ValueChip(
                label: 'Do am',
                value: _formatNumber(telemetry.humidity, suffix: '%'),
              ),
              _ValueChip(
                label: 'Lux',
                value: _formatNumber(telemetry.lux, precision: 0),
              ),
              _ValueChip(
                label: 'Sensor',
                value: telemetry.sensorFault ? 'Fault' : 'OK',
              ),
              _ValueChip(
                label: 'Override',
                value: telemetry.userOverride ? 'ON' : 'OFF',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Relay: H:${_state(telemetry.relays.heater)} '
            'M:${_state(telemetry.relays.mist)} '
            'F:${_state(telemetry.relays.fan)} '
            'L:${_state(telemetry.relays.light)}',
            style: const TextStyle(fontSize: 12.5, color: AppTheme.subtle),
          ),
        ],
      ),
    );
  }

  static String _formatTimestamp(DateTime dateTime) {
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute:$second';
  }

  static String _formatNumber(
    double? value, {
    int precision = 1,
    String suffix = '',
  }) {
    if (value == null) {
      return '--';
    }
    return '${value.toStringAsFixed(precision)}$suffix';
  }

  static String _state(bool enabled) => enabled ? 'ON' : 'OFF';
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2A3530)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _JwtSessionInfo {
  const _JwtSessionInfo({
    this.userId,
    this.issuedAt,
    this.expiresAt,
  });

  final String? userId;
  final DateTime? issuedAt;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!.toUtc());

  static _JwtSessionInfo fromToken(String? token) {
    if (token == null || token.isEmpty) {
      return const _JwtSessionInfo();
    }

    final segments = token.split('.');
    if (segments.length < 2) {
      return const _JwtSessionInfo();
    }

    try {
      final payloadSegment = base64Url.normalize(segments[1]);
      final payloadRaw = utf8.decode(base64Url.decode(payloadSegment));
      final payload = jsonDecode(payloadRaw);

      if (payload is! Map<String, dynamic>) {
        return const _JwtSessionInfo();
      }

      return _JwtSessionInfo(
        userId: _readString(payload['userId']),
        issuedAt: _readEpochSeconds(payload['iat']),
        expiresAt: _readEpochSeconds(payload['exp']),
      );
    } catch (_) {
      return const _JwtSessionInfo();
    }
  }

  static String? _readString(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static DateTime? _readEpochSeconds(Object? value) {
    int? seconds;

    if (value is int) {
      seconds = value;
    } else if (value is num) {
      seconds = value.toInt();
    } else if (value is String) {
      seconds = int.tryParse(value);
    }

    if (seconds == null) return null;

    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
        .toLocal();
  }
}
