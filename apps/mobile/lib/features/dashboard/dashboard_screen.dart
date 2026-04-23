// apps/mobile/lib/features/dashboard/presentation/dashboard_screen.dart
import 'dart:ui';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../core/services/auth_service.dart';
import '../../core/constants/app_constants.dart';
import 'data/chat_history_store.dart';
import 'data/chatbox_repository.dart';
import 'data/device_control_repository.dart';
import 'domain/chatbox_models.dart';

enum AppThemeMode { day, auto, night }

enum _MetricStatus { missing, low, normal, high }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _bgController;
  late AnimationController _particleController;
  late AnimationController _themeController;
  late PageController _pageController;

  final ScrollController _historyScrollController = ScrollController();

  AppThemeMode _currentThemeMode = AppThemeMode.auto;
  int _currentIndex = 1;

  final AuthService _authService = AuthService();
  final DeviceControlRepository _controlRepo = DeviceControlRepository();
  final ChatHistoryStore _chatHistoryStore = ChatHistoryStore();
  final ChatboxRepository _chatboxRepository = ChatboxRepository();

  bool _isSyncingData = false;
  bool _isHydratingChatHistory = false;
  bool _isSendingChatMessage = false;
  String? _chatboxError;
  DateTime? _chatboxUpdatedAt;
  List<ChatboxMessage> _chatMessages = const <ChatboxMessage>[];
  List<String> _chatSuggestions = const <String>[];

  // --- BIẾN STATE CHO TAB HỒ SƠ ---
  String _userIdDisplay = "Loading...";
  String _userName = "Đang tải...";

  // --- BIẾN STATE CHO TAB LỊCH SỬ ---
  double? _currentTemp;
  double? _currentHum;
  List<double?> _tempHistory = [];
  List<double?> _humHistory = [];
  List<String> _timeHistory = [];

  final List<String> _intervalKeys = ['1m', '5m', '10m', '30m', '1h', '6h'];
  final List<String> _intervalLabels = [
    '1 Phút',
    '5 Phút',
    '10 Phút',
    '30 Phút',
    '1 Giờ',
    '6 Giờ'
  ];
  String _selectedInterval = '1m';

  List<Map<String, dynamic>> _tableData = [];
  bool _isLoadingMore = false;
  int _currentLimit = 10; // Biến lưu số lượng bản ghi cần tải

  // --- BIẾN STATE THIẾT BỊ ---
  bool isLightOn = false;
  bool isHeatOn = false;
  bool isMistOn = false;
  bool isFanOn = false;

  bool get _isCurrentlyDark {
    if (_currentThemeMode == AppThemeMode.night) return true;
    if (_currentThemeMode == AppThemeMode.day) return false;
    final hour = DateTime.now().hour;
    return hour < 6 || hour >= 18;
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _bgController =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..repeat();
    _particleController =
        AnimationController(vsync: this, duration: const Duration(seconds: 15))
          ..repeat();
    _themeController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1000),
        value: _isCurrentlyDark ? 1.0 : 0.0);

    // Lắng nghe sự kiện cuộn để tải thêm
    _historyScrollController.addListener(() {
      if (_historyScrollController.position.pixels >=
          _historyScrollController.position.maxScrollExtent - 50) {
        _loadMoreData();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserProfile();
      _syncDataFromDatabase(resetPagination: true);
      _loadChatHistoryIfNeeded();
    });
  }

  @override
  void dispose() {
    _historyScrollController.dispose();
    _bgController.dispose();
    _particleController.dispose();
    _themeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // Hàm tải thêm dữ liệu khi cuộn xuống đáy
  Future<void> _loadMoreData() async {
    if (_isLoadingMore || _isSyncingData) return;

    setState(() {
      _isLoadingMore = true;
      _currentLimit += 10;
    });

    await _syncDataFromDatabase(resetPagination: false);
  }

  // Lấy User từ Token hoặc DB
  String? _extractUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      String payload = parts[1];
      while (payload.length % 4 != 0) {
        payload += '=';
      }

      final decodedPayload = utf8.decode(base64Url.decode(payload));
      final payloadMap = jsonDecode(decodedPayload);
      if (payloadMap is! Map<String, dynamic>) return null;

      final userIdRaw = payloadMap['userId'] ?? payloadMap['sub'];
      if (userIdRaw is! String) return null;

      final userId = userIdRaw.trim();
      return userId.isEmpty ? null : userId;
    } catch (_) {
      return null;
    }
  }

  String? _extractUserNameFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      String payload = parts[1];
      while (payload.length % 4 != 0) {
        payload += '=';
      }

      final decodedPayload = utf8.decode(base64Url.decode(payload));
      final payloadMap = jsonDecode(decodedPayload);
      if (payloadMap is! Map<String, dynamic>) return null;

      final emailRaw = payloadMap['email'];
      if (emailRaw is! String) return null;

      final email = emailRaw.trim();
      if (email.isEmpty) return null;
      return email.split('@').first.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final token = await _authService.getToken();
      final storedUserId = (await _authService.getUserId())?.trim();
      final tokenUserId = token == null ? null : _extractUserIdFromToken(token);
      final tokenUserName =
          token == null ? null : _extractUserNameFromToken(token);
      String? telemetryUserId;

      if (token != null && storedUserId != null && storedUserId.isNotEmpty) {
        try {
          final telemetryUrl = Uri.parse(
            '${AppConstants.apiBaseUrl}/api/devices/$storedUserId/telemetry?limit=1',
          );
          final teleResponse = await http.get(telemetryUrl, headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          });

          if (teleResponse.statusCode == 200) {
            final decoded = jsonDecode(teleResponse.body);
            if (decoded is Map<String, dynamic>) {
              final teleList = decoded['telemetry'];
              if (teleList is List && teleList.isNotEmpty) {
                final first = teleList.first;
                if (first is Map<String, dynamic>) {
                  final fromDb = first['userId']?.toString().trim();
                  if (fromDb != null && fromDb.isNotEmpty) {
                    telemetryUserId = fromDb;
                  }
                }
              }
            }
          }
        } catch (_) {
          // Keep fallback sources when telemetry lookup fails.
        }
      }

      final resolvedUserId =
          (telemetryUserId != null && telemetryUserId.isNotEmpty)
              ? telemetryUserId
              : (storedUserId != null && storedUserId.isNotEmpty)
                  ? storedUserId
                  : tokenUserId;

      if (!mounted) return;

      setState(() {
        if (resolvedUserId != null && resolvedUserId.isNotEmpty) {
          _userIdDisplay = resolvedUserId;
        } else {
          _userIdDisplay = 'User ID unavailable';
        }

        if (tokenUserName != null && tokenUserName.isNotEmpty) {
          _userName = tokenUserName;
        }
      });
    } catch (e) {
      debugPrint('Lỗi tải thông tin User ID: $e');
      if (mounted) {
        setState(() {
          _userIdDisplay = 'User ID unavailable';
        });
      }
    }
  }

  void _setThemeMode(AppThemeMode mode) {
    if (_currentThemeMode == mode) return;
    setState(() => _currentThemeMode = mode);
    if (_isCurrentlyDark) {
      _themeController.forward();
    } else {
      _themeController.reverse();
    }
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(index,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutQuart);
  }

  Future<void> _handleLogout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _copyUserId() async {
    final value = _userIdDisplay.trim();
    if (value.isEmpty ||
        value == 'Loading...' ||
        value == 'User ID unavailable') {
      return;
    }

    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã sao chép IdUser'),
        duration: Duration(milliseconds: 900),
      ),
    );
  }

  Future<void> _syncDataFromDatabase({bool resetPagination = false}) async {
    if (_isSyncingData) return;

    setState(() {
      _isSyncingData = true;
      if (resetPagination) {
        _currentLimit = 10;
        _tempHistory.clear();
        _humHistory.clear();
        _timeHistory.clear();
        _tableData.clear();
      }
    });

    try {
      final token = await _authService.getToken();
      final userId = await _authService.getUserId();
      if (token == null || userId == null) {
        throw Exception('Xác thực thất bại.');
      }

      final controlSnapshot =
          await _controlRepo.fetchCurrentState(userId: userId, token: token);
      if (mounted) {
        setState(() {
          isLightOn = controlSnapshot.state.light;
          isHeatOn = controlSnapshot.state.heater;
          isMistOn = controlSnapshot.state.mist;
          isFanOn = controlSnapshot.state.fan;
        });
      }

      final telemetryUrl = Uri.parse(
          '${AppConstants.apiBaseUrl}/api/devices/$userId/telemetry?limit=$_currentLimit');
      final teleResponse = await http.get(telemetryUrl, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });

      if (teleResponse.statusCode != 200) {
        throw Exception(
            'Không thể tải telemetry (HTTP ${teleResponse.statusCode}).');
      }

      final decoded = jsonDecode(teleResponse.body) as Map<String, dynamic>;
      final teleList = decoded['telemetry'] as List?;
      final rows = <Map<String, dynamic>>[];

      if (teleList != null) {
        for (final entry in teleList.whereType<Map<String, dynamic>>()) {
          if (entry['userId']?.toString() != userId) continue;

          final rawTime = entry['timestamp'] ?? entry['createdAt'];
          if (rawTime == null) continue;

          final parsedTime = DateTime.tryParse(rawTime.toString());
          if (parsedTime == null) continue;
          final localTime = parsedTime.toLocal();

          final tempVal = _toNullableDouble(entry['temperature']);
          final humVal = _toNullableDouble(entry['humidity']);

          rows.add({
            'timestamp': localTime,
            'temp': tempVal,
            'hum': humVal,
            'time':
                '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}:${localTime.second.toString().padLeft(2, '0')}',
            'date':
                '${localTime.day.toString().padLeft(2, '0')}/${localTime.month.toString().padLeft(2, '0')}/${localTime.year}',
          });
        }
      }

      rows.sort((a, b) =>
          (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));
      final latestRows = rows.take(_currentLimit).toList(growable: false);

      // Lấy 10 phần tử mới nhất để vẽ biểu đồ
      final chartSourceRows =
          latestRows.take(5).toList().reversed.toList(growable: false);

      final temps = chartSourceRows
          .map<double?>((row) => row['temp'] as double?)
          .toList();
      final hums =
          chartSourceRows.map<double?>((row) => row['hum'] as double?).toList();
      final times =
          chartSourceRows.map<String>((row) => row['time'] as String).toList();

      while (temps.length < 5) {
        temps.insert(0, null);
        hums.insert(0, null);
        times.insert(0, '--:--:--');
      }

      if (mounted) {
        setState(() {
          _tempHistory = temps;
          _humHistory = hums;
          _timeHistory = times;
          _tableData = latestRows;

          if (latestRows.isNotEmpty) {
            _currentTemp = latestRows.first['temp'] as double?;
            _currentHum = latestRows.first['hum'] as double?;
          } else {
            _currentTemp = null;
            _currentHum = null;
          }
        });
      }

      if (mounted && resetPagination) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đã cập nhật dữ liệu mới.'),
          duration: Duration(milliseconds: 900),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Lỗi đồng bộ: $e'),
            backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingData = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  double? _toNullableDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  _MetricStatus _metricStatus(
    double? value, {
    required double low,
    required double high,
  }) {
    if (value == null) return _MetricStatus.missing;
    if (value < low) return _MetricStatus.low;
    if (value > high) return _MetricStatus.high;
    return _MetricStatus.normal;
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }

  String _buildAiStatusMessage() {
    final tempStatus = _metricStatus(_currentTemp, low: 24, high: 28);
    final humStatus = _metricStatus(_currentHum, low: 70, high: 85);

    if (tempStatus == _MetricStatus.missing &&
        humStatus == _MetricStatus.missing) {
      return 'Không có dữ liệu nhiệt độ và độ ẩm.';
    }

    if (tempStatus == _MetricStatus.missing) {
      switch (humStatus) {
        case _MetricStatus.low:
          return 'Không có dữ liệu nhiệt độ, độ ẩm đang thấp.';
        case _MetricStatus.high:
          return 'Không có dữ liệu nhiệt độ, độ ẩm đang quá cao.';
        case _MetricStatus.normal:
          return 'Không có dữ liệu nhiệt độ, độ ẩm đang trong ngưỡng ổn định.';
        case _MetricStatus.missing:
          return 'Không có dữ liệu nhiệt độ và độ ẩm.';
      }
    }

    if (humStatus == _MetricStatus.missing) {
      switch (tempStatus) {
        case _MetricStatus.low:
          return 'Nhiệt độ đang thấp, không có dữ liệu độ ẩm.';
        case _MetricStatus.high:
          return 'Nhiệt độ đang cao, không có dữ liệu độ ẩm.';
        case _MetricStatus.normal:
          return 'Nhiệt độ đang trong ngưỡng ổn định, không có dữ liệu độ ẩm.';
        case _MetricStatus.missing:
          return 'Không có dữ liệu nhiệt độ và độ ẩm.';
      }
    }

    if (tempStatus == _MetricStatus.normal &&
        humStatus == _MetricStatus.normal) {
      return 'Nhiệt độ và độ ẩm đang trong ngưỡng ổn định.';
    }

    String? tempPhrase;
    if (tempStatus == _MetricStatus.low) {
      tempPhrase = 'nhiệt độ đang thấp';
    } else if (tempStatus == _MetricStatus.high) {
      tempPhrase = 'nhiệt độ đang cao';
    }

    String? humPhrase;
    if (humStatus == _MetricStatus.low) {
      humPhrase = 'độ ẩm đang thấp';
    } else if (humStatus == _MetricStatus.high) {
      humPhrase = 'độ ẩm đang quá cao';
    }

    if (tempPhrase != null && humPhrase != null) {
      return '${_capitalizeFirst(tempPhrase)} và $humPhrase.';
    }
    if (tempPhrase != null) {
      return '${_capitalizeFirst(tempPhrase)}, độ ẩm đang trong ngưỡng ổn định.';
    }
    if (humPhrase != null) {
      return '${_capitalizeFirst(humPhrase)}, nhiệt độ đang trong ngưỡng ổn định.';
    }

    return 'Không xác định được trạng thái vi khí hậu hiện tại.';
  }

  bool _isContextRequest(String message) {
    final normalized = message.toLowerCase().trim();
    const contextKeywords = <String>[
      'context',
      'ngữ cảnh',
      'ngu canh',
      'lấy ngữ cảnh',
      'lay ngu canh',
      'bối cảnh',
      'boi canh',
      'toàn cảnh',
      'toan canh',
      'tổng quan',
      'tong quan',
    ];
    return contextKeywords.any(normalized.contains);
  }

  String _formatChatTime(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  String _buildFriendlyChatError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) {
      return 'Không thể kết nối trợ lý AI lúc này.';
    }
    return message;
  }

  Future<void> _loadChatHistoryIfNeeded() async {
    if (_isHydratingChatHistory || _chatMessages.isNotEmpty) return;

    if (mounted) {
      setState(() {
        _isHydratingChatHistory = true;
        _chatboxError = null;
      });
    }

    try {
      final userId = (await _authService.getUserId())?.trim();
      if (userId == null || userId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _chatMessages = <ChatboxMessage>[
            ChatboxMessage.assistant(
              'Không tìm thấy IdUser trong phiên đăng nhập hiện tại.',
            ),
          ];
        });
        return;
      }

      final persisted = await _chatHistoryStore.readHistory(userId);
      final hydratedMessages = persisted.isNotEmpty
          ? persisted
          : <ChatboxMessage>[
              ChatboxMessage.assistant(
                'Xin chào, mình là Trợ lý AI của Hermit Home.',
              ),
              ChatboxMessage.assistant(_buildAiStatusMessage()),
            ];

      if (!mounted) return;
      setState(() {
        _chatMessages = hydratedMessages;
      });

      if (persisted.isEmpty) {
        await _chatHistoryStore.writeHistory(userId, hydratedMessages);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _chatboxError = _buildFriendlyChatError(error);
        if (_chatMessages.isEmpty) {
          _chatMessages = <ChatboxMessage>[
            ChatboxMessage.assistant(
              'Không thể tải lịch sử chat. Bạn vẫn có thể nhắn tin mới.',
            ),
          ];
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isHydratingChatHistory = false;
        });
      }
    }
  }

  Future<void> _persistChatHistory() async {
    final userId = (await _authService.getUserId())?.trim();
    if (userId == null || userId.isEmpty) return;
    try {
      await _chatHistoryStore.writeHistory(userId, _chatMessages);
    } catch (_) {
      // Ignore local storage errors to avoid blocking chat interactions.
    }
  }

  Future<void> _clearChatHistory() async {
    final userId = (await _authService.getUserId())?.trim();
    if (userId == null || userId.isEmpty) return;
    try {
      await _chatHistoryStore.clearHistory(userId);
    } catch (_) {
      // Ignore local clear errors. New history will overwrite stale entries.
    }
  }

  void _scrollChatToBottom(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openAiChatDialog(Color textMain, Color accentColor) async {
    await _loadChatHistoryIfNeeded();
    if (!mounted) return;

    final inputController = TextEditingController();
    final scrollController = ScrollController();
    var didInitialScroll = false;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              if (!didInitialScroll && _chatMessages.isNotEmpty) {
                didInitialScroll = true;
                _scrollChatToBottom(scrollController);
              }

              Future<void> sendMessage({
                String? preset,
                bool forceContext = false,
              }) async {
                final raw = (preset ?? inputController.text).trim();
                if (raw.isEmpty || _isSendingChatMessage) return;

                final historyBeforeSend = List<ChatboxMessage>.from(
                  _chatMessages,
                );

                setDialogState(() {
                  _chatMessages = <ChatboxMessage>[
                    ..._chatMessages,
                    ChatboxMessage.user(raw),
                  ];
                  _isSendingChatMessage = true;
                  _chatboxError = null;
                });

                if (preset == null) {
                  inputController.clear();
                }
                _scrollChatToBottom(scrollController);

                try {
                  final token = (await _authService.getToken())?.trim();
                  final userId = (await _authService.getUserId())?.trim();
                  if (token == null ||
                      token.isEmpty ||
                      userId == null ||
                      userId.isEmpty) {
                    throw Exception('Không tìm thấy phiên đăng nhập hợp lệ.');
                  }

                  final reply = await _chatboxRepository.sendMessage(
                    userId: userId,
                    token: token,
                    message: raw,
                    history: historyBeforeSend,
                    requestContext: forceContext || _isContextRequest(raw),
                  );

                  final answer = reply.answer.trim().isEmpty
                      ? 'Trợ lý AI chưa trả lời hợp lệ, bạn thử lại nhé.'
                      : reply.answer.trim();

                  if (!mounted) return;
                  if (!context.mounted) {
                    setState(() {
                      _chatMessages = <ChatboxMessage>[
                        ..._chatMessages,
                        ChatboxMessage.assistant(answer),
                      ];
                      _chatSuggestions = reply.suggestions;
                      _chatboxUpdatedAt = DateTime.now();
                      _chatboxError = null;
                      _isSendingChatMessage = false;
                    });
                    await _persistChatHistory();
                    return;
                  }

                  setDialogState(() {
                    _chatMessages = <ChatboxMessage>[
                      ..._chatMessages,
                      ChatboxMessage.assistant(answer),
                    ];
                    _chatSuggestions = reply.suggestions;
                    _chatboxUpdatedAt = DateTime.now();
                    _chatboxError = null;
                    _isSendingChatMessage = false;
                  });

                  await _persistChatHistory();
                } catch (error) {
                  if (!mounted) return;
                  final errorMessage = _buildFriendlyChatError(error);

                  if (!context.mounted) {
                    setState(() {
                      _chatMessages = <ChatboxMessage>[
                        ..._chatMessages,
                        ChatboxMessage.assistant(
                          'Không gửi được tin nhắn: $errorMessage',
                        ),
                      ];
                      _chatboxError = errorMessage;
                      _isSendingChatMessage = false;
                    });
                    await _persistChatHistory();
                    return;
                  }

                  setDialogState(() {
                    _chatMessages = <ChatboxMessage>[
                      ..._chatMessages,
                      ChatboxMessage.assistant(
                        'Không gửi được tin nhắn: $errorMessage',
                      ),
                    ];
                    _chatboxError = errorMessage;
                    _isSendingChatMessage = false;
                  });

                  await _persistChatHistory();
                } finally {
                  _scrollChatToBottom(scrollController);
                }
              }

              Future<void> clearHistory() async {
                if (_isSendingChatMessage) return;

                setDialogState(() {
                  _chatMessages = <ChatboxMessage>[
                    ChatboxMessage.assistant(
                      'Lịch sử chat đã được xóa.',
                    ),
                    ChatboxMessage.assistant(_buildAiStatusMessage()),
                  ];
                  _chatSuggestions = const <String>[];
                  _chatboxError = null;
                  _chatboxUpdatedAt = null;
                });

                await _clearChatHistory();
                await _persistChatHistory();
                _scrollChatToBottom(scrollController);
              }

              return ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 560),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: accentColor.withOpacity(0.45),
                        width: 1.4,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: accentColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Trợ lý AI',
                                style: TextStyle(
                                  color: textMain,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              icon: Icon(
                                Icons.close_rounded,
                                color: textMain.withOpacity(0.8),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_chatboxUpdatedAt != null) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Đồng bộ lần cuối: ${_formatChatTime(_chatboxUpdatedAt!)}',
                              style: TextStyle(
                                color: textMain.withOpacity(0.65),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (_chatboxError != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.redAccent.withOpacity(0.35),
                              ),
                            ),
                            child: Text(
                              _chatboxError!,
                              style: TextStyle(
                                color: textMain,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _isSendingChatMessage
                                  ? null
                                  : () => sendMessage(
                                        preset: 'Lấy ngữ cảnh hiện tại',
                                        forceContext: true,
                                      ),
                              icon: const Icon(Icons.dataset_linked_rounded),
                              label: const Text('Lấy ngữ cảnh'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: accentColor,
                                side: BorderSide(
                                  color: accentColor.withOpacity(0.55),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  _chatMessages.isEmpty ? null : clearHistory,
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('Xóa lịch sử'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: textMain.withOpacity(0.85),
                                side: BorderSide(
                                  color: textMain.withOpacity(0.3),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                        if (_chatSuggestions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 34,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _chatSuggestions.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final tip = _chatSuggestions[index];
                                return ActionChip(
                                  label: Text(
                                    tip,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onPressed: _isSendingChatMessage
                                      ? null
                                      : () => sendMessage(preset: tip),
                                  labelStyle: TextStyle(
                                    color: textMain,
                                    fontSize: 12,
                                  ),
                                  backgroundColor:
                                      Colors.white.withOpacity(0.1),
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(0.2),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            controller: scrollController,
                            itemCount: _chatMessages.length,
                            itemBuilder: (context, index) {
                              final msg = _chatMessages[index];
                              final align = msg.isUser
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft;
                              final bgColor = msg.isUser
                                  ? accentColor.withOpacity(0.24)
                                  : Colors.white.withOpacity(0.12);

                              return Align(
                                alignment: align,
                                child: Container(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  constraints:
                                      const BoxConstraints(maxWidth: 280),
                                  decoration: BoxDecoration(
                                    color: bgColor,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.15),
                                    ),
                                  ),
                                  child: Text(
                                    msg.content,
                                    style: TextStyle(
                                      color: textMain,
                                      fontSize: 13.5,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: inputController,
                                textInputAction: TextInputAction.send,
                                minLines: 1,
                                maxLines: 3,
                                enabled: !_isSendingChatMessage,
                                onSubmitted: (_) => sendMessage(),
                                style: TextStyle(color: textMain),
                                decoration: InputDecoration(
                                  hintText: 'Nhập tin nhắn...',
                                  hintStyle: TextStyle(
                                      color: textMain.withOpacity(0.6)),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.1),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.white.withOpacity(0.2),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.white.withOpacity(0.2),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: accentColor),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed:
                                  _isSendingChatMessage ? null : sendMessage,
                              icon: _isSendingChatMessage
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: accentColor,
                                      ),
                                    )
                                  : Icon(
                                      Icons.send_rounded,
                                      color: accentColor,
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      inputController.dispose();
      scrollController.dispose();
    });
  }

  Future<void> _toggleDevice(String deviceKey, bool enabled) async {
    setState(() {
      if (deviceKey == 'light') isLightOn = enabled;
      if (deviceKey == 'heater') isHeatOn = enabled;
      if (deviceKey == 'mist') isMistOn = enabled;
      if (deviceKey == 'fan') isFanOn = enabled;
    });

    try {
      final token = await _authService.getToken();
      final userId = await _authService.getUserId();
      await _controlRepo.setDeviceState(
          userId: userId!,
          token: token!,
          deviceKey: deviceKey,
          enabled: enabled);
    } catch (e) {
      if (mounted) {
        setState(() {
          if (deviceKey == 'light') isLightOn = !enabled;
          if (deviceKey == 'heater') isHeatOn = !enabled;
          if (deviceKey == 'mist') isMistOn = !enabled;
          if (deviceKey == 'fan') isFanOn = !enabled;
        });
      }
    }
  }

  void _showGlassDialog(String title, Widget content) {
    showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.6),
        builder: (context) {
          double t = _themeController.value;
          Color glassBg = Color.lerp(Colors.white.withOpacity(0.15),
              const Color(0xFF001A33).withOpacity(0.85), t)!;
          Color glassBorder = Color.lerp(Colors.white.withOpacity(0.5),
              Colors.cyanAccent.withOpacity(0.3), t)!;

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: glassBg,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: glassBorder, width: 1.5),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2)),
                        ),
                        const SizedBox(height: 25),
                        content,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, child) {
        double t = _themeController.value;

        // BẢNG MÀU ĐÃ CẬP NHẬT
        Color bgCenter =
            Color.lerp(const Color(0xFFE1F5FE), const Color(0xFF002D5E), t)!;
        Color bgEdge =
            Color.lerp(const Color(0xFF4FC3F7), const Color(0xFF000B18), t)!;

        Color wave1 = Color.lerp(Colors.white.withOpacity(0.6),
            const Color(0xFF006DFF).withOpacity(0.2), t)!;
        Color wave2 = Color.lerp(Colors.white.withOpacity(0.4),
            const Color(0xFF00D2FF).withOpacity(0.15), t)!;
        Color wave3 = Color.lerp(Colors.white.withOpacity(0.2),
            const Color(0xFF00F2FF).withOpacity(0.1), t)!;

        Color particleColor = Color.lerp(
            const Color(0xFF0288D1).withOpacity(0.4),
            Colors.cyanAccent.withOpacity(0.25),
            t)!;
        Color accentColor =
            Color.lerp(const Color(0xFFE65100), const Color(0xFF00D2FF), t)!;

        // TEXT BAN NGÀY SẼ DÙNG MÀU TỐI, BAN ĐÊM DÙNG MÀU SÁNG
        Color textMain = Color.lerp(const Color(0xFF001E36), Colors.white, t)!;

        // NỀN KÍNH BAN NGÀY ĐỤC HƠN
        Color glassBg = Color.lerp(
            Colors.white.withOpacity(0.55), Colors.white.withOpacity(0.08), t)!;
        Color glassBorder = Color.lerp(
            Colors.white.withOpacity(0.9), Colors.white.withOpacity(0.15), t)!;

        return Scaffold(
          backgroundColor: bgEdge,
          body: Stack(
            children: [
              Container(
                  decoration: BoxDecoration(
                      gradient: RadialGradient(
                          center: Alignment.topLeft,
                          radius: 1.5,
                          colors: [bgCenter, bgEdge]))),
              AnimatedBuilder(
                animation: _particleController,
                builder: (context, child) => CustomPaint(
                  painter: ParticlePainter(
                      progress: _particleController.value,
                      color: particleColor),
                  child: Container(),
                ),
              ),
              AnimatedBuilder(
                animation: _bgController,
                builder: (context, child) => Stack(
                  children: [
                    _buildWave(1, 1.0, 0.65, wave1, 0.0, t > 0.5),
                    _buildWave(-1, 1.3, 0.75, wave2, pi, t > 0.5),
                    _buildWave(2, 0.8, 0.85, wave3, pi / 2, t > 0.5),
                  ],
                ),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _currentIndex == 0
                                    ? "Lịch Sử Bể"
                                    : _currentIndex == 1
                                        ? "Hang Chính"
                                        : "Hồ Sơ",
                                style: TextStyle(
                                    color: textMain,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _buildDraggableThemeToggle(accentColor, textMain),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        onPageChanged: (index) =>
                            setState(() => _currentIndex = index),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _buildHistoryTab(
                              glassBg, glassBorder, textMain, accentColor),
                          _buildHomeTab(
                              glassBg, glassBorder, textMain, accentColor),
                          _buildProfileTab(
                              glassBg, glassBorder, textMain, accentColor),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _buildGlassBottomNav(
                    glassBg, glassBorder, accentColor, textMain),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- TAB 0: LỊCH SỬ (HISTORY) ---
  Widget _buildHistoryTab(
      Color glassBg, Color glassBorder, Color textMain, Color accentColor) {
    return RefreshIndicator(
      color: accentColor,
      backgroundColor: const Color(0xFF001A33),
      onRefresh: () async {
        await _syncDataFromDatabase(resetPagination: true);
      },
      child: SingleChildScrollView(
        controller: _historyScrollController,
        physics:
            const AlwaysScrollableScrollPhysics(), // Đảm bảo luôn cuộn được để pull-to-refresh hoạt động
        padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text("Lọc dữ liệu",
                style:
                    TextStyle(color: textMain.withOpacity(0.8), fontSize: 14)),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_intervalKeys.length, (index) {
                  final key = _intervalKeys[index];
                  final label = _intervalLabels[index];
                  final isSelected = _selectedInterval == key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () {
                        if (_selectedInterval != key) {
                          setState(() => _selectedInterval = key);
                          _syncDataFromDatabase(resetPagination: true);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accentColor.withOpacity(0.3)
                              : glassBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: isSelected ? accentColor : glassBorder,
                              width: 1),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                              color: isSelected
                                  ? textMain
                                  : textMain.withOpacity(0.7),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 20),
            _buildChartCard("Biến Động Nhiệt Độ", "°C", accentColor, glassBg,
                glassBorder, textMain, _tempHistory, _timeHistory),
            const SizedBox(height: 20),
            _buildChartCard("Biến Động Độ Ẩm", "%", const Color(0xFF0288D1),
                glassBg, glassBorder, textMain, _humHistory, _timeHistory),
            const SizedBox(height: 30),
            Text("Chi Tiết Thông Số",
                style: TextStyle(
                    color: textMain,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
            const SizedBox(height: 15),
            _buildDataTable(glassBg, glassBorder, textMain, accentColor),
            if (_isLoadingMore)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Center(
                    child: CircularProgressIndicator(
                        color: accentColor, strokeWidth: 2)),
              ),
            if (_tableData.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text("Đang hiển thị $_currentLimit bản ghi",
                      style: TextStyle(
                          color: textMain.withOpacity(0.6), fontSize: 12)),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildDataTable(
      Color glassBg, Color glassBorder, Color textMain, Color accentColor) {
    if (_isSyncingData && _tableData.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: CircularProgressIndicator(color: accentColor),
        ),
      );
    }
    if (_tableData.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text("Không có dữ liệu cho mốc thời gian này.",
              style: TextStyle(color: textMain.withOpacity(0.5))),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
              color: glassBg,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: glassBorder, width: 1.5)),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                decoration: BoxDecoration(
                    color: textMain.withOpacity(0.05),
                    border: Border(bottom: BorderSide(color: glassBorder))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        flex: 2,
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text("Thời gian",
                                style: TextStyle(
                                    color: textMain.withOpacity(0.8),
                                    fontWeight: FontWeight.bold)))),
                    Expanded(
                        flex: 1,
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Text("Nhiệt",
                                style: TextStyle(
                                    color: textMain.withOpacity(0.8),
                                    fontWeight: FontWeight.bold)))),
                    Expanded(
                        flex: 1,
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text("Ẩm",
                                style: TextStyle(
                                    color: textMain.withOpacity(0.8),
                                    fontWeight: FontWeight.bold)))),
                  ],
                ),
              ),
              ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: _tableData.length,
                itemBuilder: (context, index) {
                  final item = _tableData[index];
                  final tempValue = item['temp'] as double?;
                  final humValue = item['hum'] as double?;
                  final tempText = tempValue != null
                      ? '${tempValue.toStringAsFixed(1)}°C'
                      : '--';
                  final humText = humValue != null
                      ? '${humValue.toStringAsFixed(1)}%'
                      : '--';
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 15),
                    decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: glassBorder.withOpacity(0.5)))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(item['date'],
                                        style: TextStyle(
                                            color: textMain,
                                            fontWeight: FontWeight.bold))),
                                FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(item['time'],
                                        style: TextStyle(
                                            color: textMain.withOpacity(0.6),
                                            fontSize: 11))),
                              ],
                            )),
                        Expanded(
                            flex: 1,
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: Text(tempText,
                                    style: TextStyle(
                                        color: accentColor,
                                        fontWeight: FontWeight.w600)))),
                        Expanded(
                            flex: 1,
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(humText,
                                    style: const TextStyle(
                                        color: Color(0xFF0288D1),
                                        fontWeight: FontWeight.w600)))),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard(
      String title,
      String unit,
      Color lineColor,
      Color glassBg,
      Color glassBorder,
      Color textMain,
      List<double?> data,
      List<String> times) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: glassBg,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: glassBorder, width: 1.5)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text("$title ($unit)",
                    style: TextStyle(
                        color: textMain,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 25),
              SizedBox(
                height: 160,
                width: double.infinity,
                child: CustomPaint(
                  painter: LineChartPainter(
                      data: data,
                      timeLabels: times,
                      unit: unit,
                      lineColor: lineColor,
                      textColor: textMain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- TAB 1: HANG CHÍNH (HOME) ---
  Widget _buildHomeTab(
      Color glassBg, Color glassBorder, Color textMain, Color accentColor) {
    final tempStr =
        _currentTemp != null ? _currentTemp!.toStringAsFixed(1) : "--";
    final humStr = _currentHum != null ? _currentHum!.toStringAsFixed(0) : "--";

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                    color: glassBg,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: glassBorder, width: 1.5)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text("Thông số hiện tại",
                                style: TextStyle(
                                    color: textMain.withOpacity(0.8),
                                    fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _isSyncingData
                              ? null
                              : () =>
                                  _syncDataFromDatabase(resetPagination: true),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isSyncingData)
                                SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                        color: accentColor, strokeWidth: 2))
                              else
                                Icon(Icons.sync_rounded,
                                    color: accentColor, size: 16),
                              const SizedBox(width: 5),
                              Text(
                                  _isSyncingData
                                      ? "Đang đồng bộ..."
                                      : "Làm mới",
                                  style: TextStyle(
                                      color: accentColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: _buildTelemetryItem(Icons.thermostat_rounded,
                              "Nhiệt Độ", tempStr, "°C", accentColor, textMain),
                        ),
                        Container(
                            width: 1,
                            height: 50,
                            color: textMain.withOpacity(0.2)),
                        Expanded(
                          child: _buildTelemetryItem(Icons.water_drop_rounded,
                              "Độ Ẩm", humStr, "%", accentColor, textMain),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),
                    _buildAIStatusCard(textMain, accentColor),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Text("Điều Khiển Thiết Bị",
              style: TextStyle(
                  color: textMain,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2)),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                  child: _buildDeviceCard(
                      "Đèn Sáng",
                      Icons.lightbulb_rounded,
                      isLightOn,
                      (val) => _toggleDevice('light', val),
                      glassBg,
                      glassBorder,
                      accentColor,
                      textMain)),
              const SizedBox(width: 15),
              Expanded(
                  child: _buildDeviceCard(
                      "Sưởi Ấm",
                      Icons.local_fire_department_rounded,
                      isHeatOn,
                      (val) => _toggleDevice('heater', val),
                      glassBg,
                      glassBorder,
                      const Color(0xFFFF5252),
                      textMain)),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                  child: _buildDeviceCard(
                      "Phun Sương",
                      Icons.cloudy_snowing,
                      isMistOn,
                      (val) => _toggleDevice('mist', val),
                      glassBg,
                      glassBorder,
                      const Color(0xFF4FC3F7),
                      textMain)),
              const SizedBox(width: 15),
              Expanded(
                  child: _buildDeviceCard(
                      "Quạt Gió",
                      Icons.mode_fan_off_rounded,
                      isFanOn,
                      (val) => _toggleDevice('fan', val),
                      glassBg,
                      glassBorder,
                      Colors.grey,
                      textMain)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAIStatusCard(Color textMain, Color accentColor) {
    final statusMessage = _buildAiStatusMessage();

    return GestureDetector(
      onTap: () => _openAiChatDialog(textMain, accentColor),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: accentColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: accentColor.withOpacity(0.4), width: 1.5)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(Icons.auto_awesome_rounded,
                  color: accentColor, size: 24),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Trợ lý AI:',
                        style: TextStyle(
                            color: textMain.withOpacity(0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 4),
                  Text(statusMessage,
                      style: TextStyle(
                          color: textMain, fontSize: 14, height: 1.4)),
                  const SizedBox(height: 8),
                  Text(
                    'Nhấn để mở cửa sổ chat',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- TAB 2: HỒ SƠ (PROFILE) ---
  Widget _buildProfileTab(
      Color glassBg, Color glassBorder, Color textMain, Color accentColor) {
    final displayName =
        _userName.isNotEmpty ? "Tộc Trưởng $_userName" : "Đang tải...";
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
      child: Column(
        children: [
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(35),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                    color: glassBg,
                    borderRadius: BorderRadius.circular(35),
                    border: Border.all(color: glassBorder, width: 1.5)),
                child: Column(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor.withOpacity(0.2),
                          border: Border.all(color: accentColor, width: 2)),
                      child:
                          Icon(Icons.person_rounded, size: 50, color: textMain),
                    ),
                    const SizedBox(height: 20),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(displayName,
                          style: TextStyle(
                              color: textMain,
                              fontSize: 24,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text('IdUser: $_userIdDisplay',
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: textMain.withOpacity(0.7),
                                  fontSize: 14)),
                        ),
                        IconButton(
                          onPressed: _copyUserId,
                          tooltip: 'Sao chép IdUser',
                          icon: Icon(
                            Icons.copy_rounded,
                            size: 18,
                            color: textMain.withOpacity(0.75),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Container(height: 1, color: textMain.withOpacity(0.2)),
                    const SizedBox(height: 30),
                    _buildProfileOption(
                        Icons.settings_rounded, "Cài đặt hệ thống", textMain,
                        () {
                      _showGlassDialog(
                          "Cài đặt hệ thống",
                          Text(
                              "Tính năng cài đặt thông số đang được nâng cấp. Pháp sư vui lòng chờ bản cập nhật tiếp theo nhé!",
                              style: TextStyle(
                                  color: textMain.withOpacity(0.8),
                                  height: 1.5),
                              textAlign: TextAlign.center));
                    }),
                    const SizedBox(height: 15),
                    _buildProfileOption(Icons.notifications_rounded,
                        "Thông báo cảnh báo", textMain, () {
                      _showGlassDialog(
                          "Cảnh báo an toàn",
                          Column(children: [
                            Icon(Icons.notifications_active_outlined,
                                size: 40, color: accentColor.withOpacity(0.8)),
                            const SizedBox(height: 15),
                            Text(
                                "Chưa có cảnh báo nào! Sau này trợ lý AI sẽ theo dõi nhiệt/ẩm và gửi báo cáo khẩn cấp vào đây.",
                                style: TextStyle(
                                    color: textMain.withOpacity(0.8),
                                    height: 1.5),
                                textAlign: TextAlign.center)
                          ]));
                    }),
                    const SizedBox(height: 15),
                    _buildProfileOption(
                        Icons.help_outline_rounded, "Hỗ trợ cư dân", textMain,
                        () {
                      _showGlassDialog(
                          "Liên hệ Kỹ Thuật Viên",
                          Column(children: [
                            _buildContactRow(
                                Icons.person_outline, "Phúc (Dev)", textMain),
                            _buildContactRow(Icons.phone_iphone_rounded,
                                "0123 456 789", textMain),
                            _buildContactRow(Icons.email_outlined,
                                "phuc@hermit-home.com", textMain),
                            _buildContactRow(Icons.code_rounded,
                                "github.com/phuc-hermit", textMain),
                            _buildContactRow(Icons.work_outline_rounded,
                                "linkedin.com/in/phuc", textMain),
                          ]));
                    }),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 55),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _handleLogout,
                icon:
                    const Icon(Icons.exit_to_app_rounded, color: Colors.white),
                label: const Text("RỜI HANG",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5252),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildProfileOption(
      IconData icon, String title, Color textMain, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(icon, color: textMain.withOpacity(0.8), size: 24),
          const SizedBox(width: 15),
          Expanded(
              child: FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(title, style: TextStyle(color: textMain, fontSize: 16)),
          )),
          Icon(Icons.chevron_right_rounded, color: textMain.withOpacity(0.5)),
        ],
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String text, Color textMain) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, color: textMain.withOpacity(0.6), size: 20),
        const SizedBox(width: 15),
        Expanded(
          child: FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(text,
                style: TextStyle(
                    color: textMain,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
          ),
        )
      ]),
    );
  }

  // --- UI Helpers ---
  Widget _buildTelemetryItem(IconData icon, String label, String value,
      String unit, Color accentColor, Color textMain) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Row(
        children: [
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(icon, color: accentColor, size: 28)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      style: TextStyle(
                          color: textMain.withOpacity(0.7), fontSize: 13)),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(value,
                            style: TextStyle(
                                color: textMain,
                                fontSize: 32,
                                fontWeight: FontWeight.bold)),
                        Text(unit,
                            style: TextStyle(
                                color: textMain.withOpacity(0.7), fontSize: 16))
                      ]),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDeviceCard(
      String title,
      IconData icon,
      bool isOn,
      Function(bool) onChanged,
      Color glassBg,
      Color glassBorder,
      Color activeColor,
      Color textMain) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: isOn ? activeColor.withOpacity(0.15) : glassBg,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                  color: isOn ? activeColor.withOpacity(0.5) : glassBorder,
                  width: 1.5)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon,
                      color: isOn ? activeColor : textMain.withOpacity(0.5),
                      size: 32),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Switch(
                          value: isOn,
                          onChanged: onChanged,
                          activeColor: activeColor,
                          activeTrackColor: activeColor.withOpacity(0.3),
                          inactiveThumbColor: Colors.white70,
                          inactiveTrackColor: textMain.withOpacity(0.1)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(title,
                    style: TextStyle(
                        color: textMain,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(isOn ? "Đang chạy" : "Tạm nghỉ",
                    style: TextStyle(
                        color: isOn ? activeColor : textMain.withOpacity(0.5),
                        fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassBottomNav(
      Color glassBg, Color glassBorder, Color accentColor, Color textMain) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 25),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(35),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 70),
            child: Container(
              decoration: BoxDecoration(
                  color: glassBg,
                  borderRadius: BorderRadius.circular(35),
                  border: Border.all(color: glassBorder, width: 1.5)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                      child: _buildNavItem(0, Icons.show_chart_rounded,
                          "Lịch sử", accentColor, textMain)),
                  Expanded(
                      child: _buildNavItem(1, Icons.home_rounded, "Hang chính",
                          accentColor, textMain)),
                  Expanded(
                      child: _buildNavItem(2, Icons.person_rounded, "Hồ sơ",
                          accentColor, textMain)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label,
      Color accentColor, Color textMain) {
    bool isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
            color: isActive ? accentColor.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: isActive ? accentColor : textMain.withOpacity(0.5),
                size: 26),
            if (isActive) ...[
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      style: TextStyle(
                          color: accentColor, fontWeight: FontWeight.bold)),
                ),
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableThemeToggle(Color accentColor, Color textMain) {
    double leftPosition = 0;
    if (_currentThemeMode == AppThemeMode.auto) leftPosition = 35;
    if (_currentThemeMode == AppThemeMode.night) leftPosition = 70;

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        double dx = details.localPosition.dx;
        if (dx >= 0 && dx < 35) {
          _setThemeMode(AppThemeMode.day);
        } else if (dx >= 35 && dx < 70) {
          _setThemeMode(AppThemeMode.auto);
        } else if (dx >= 70 && dx <= 110) {
          _setThemeMode(AppThemeMode.night);
        }
      },
      onTapUp: (details) {
        double dx = details.localPosition.dx;
        if (dx < 35) {
          _setThemeMode(AppThemeMode.day);
        } else if (dx < 70) {
          _setThemeMode(AppThemeMode.auto);
        } else {
          _setThemeMode(AppThemeMode.night);
        }
      },
      child: Container(
        width: 108,
        height: 36,
        decoration: BoxDecoration(
            color: textMain.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: textMain.withOpacity(0.2), width: 1.5)),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              left: leftPosition,
              child: Container(
                  width: 35,
                  height: 33,
                  decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20))),
            ),
            Row(
              children: [
                _buildToggleIcon(
                    AppThemeMode.day, Icons.wb_sunny_rounded, textMain),
                _buildToggleIcon(AppThemeMode.auto,
                    Icons.access_time_filled_rounded, textMain),
                _buildToggleIcon(
                    AppThemeMode.night, Icons.nightlight_round, textMain),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleIcon(AppThemeMode mode, IconData icon, Color textMain) {
    return SizedBox(
        width: 35,
        height: 33,
        child: Icon(icon,
            color: _currentThemeMode == mode
                ? Colors.white
                : textMain.withOpacity(0.6),
            size: 16));
  }

  Widget _buildWave(int speed, double frequency, double height, Color color,
      double offset, bool hasGlow) {
    return CustomPaint(
        painter: WavePainter(
            progress: _bgController.value,
            speed: speed,
            frequency: frequency,
            heightFactor: height,
            color: color,
            offset: offset,
            hasGlow: hasGlow),
        child: Container());
  }
}

// --- CUSTOM PAINTERS ---

class LineChartPainter extends CustomPainter {
  final List<double?> data;
  final List<String> timeLabels;
  final String unit;
  final Color lineColor;
  final Color textColor;

  LineChartPainter(
      {required this.data,
      required this.timeLabels,
      required this.unit,
      required this.lineColor,
      required this.textColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final validData = data.whereType<double>().toList();
    if (validData.isEmpty) return;

    final maxData = validData.reduce(max);
    final minData = validData.reduce(min);
    final range = maxData - minData == 0 ? 1.0 : maxData - minData;

    final marginLeft = 35.0;
    final marginBottom = 20.0;
    final chartWidth = size.width - marginLeft;
    final chartHeight = size.height - marginBottom;
    final textStyle =
        TextStyle(color: textColor.withOpacity(0.6), fontSize: 10);

    final ySteps = [minData, minData + range / 2, maxData];
    for (var val in ySteps) {
      final normalizedY = 1 - ((val - minData) / range);
      final y = normalizedY * chartHeight;
      final tp = TextPainter(
          text: TextSpan(text: val.toStringAsFixed(1), style: textStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
      canvas.drawLine(
          Offset(marginLeft, y),
          Offset(size.width, y),
          Paint()
            ..color = textColor.withOpacity(0.1)
            ..strokeWidth = 1);
    }

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final stepX =
        data.length > 1 ? chartWidth / (data.length - 1) : chartWidth / 2;

    bool isFirstValid = true;
    double? prevX, prevY;

    for (int i = 0; i < data.length; i++) {
      final x = marginLeft + (data.length > 1 ? i * stepX : stepX);

      if (data[i] != null) {
        final normalizedY = 1 - ((data[i]! - minData) / range);
        final y = normalizedY * chartHeight;

        if (isFirstValid) {
          path.moveTo(x, y);
          isFirstValid = false;
        } else if (prevX != null && prevY != null) {
          final controlPointX = prevX! + (x - prevX) / 2;
          path.cubicTo(controlPointX, prevY, controlPointX, y, x, y);
        }

        canvas.drawCircle(
            Offset(x, y),
            4,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill);
        canvas.drawCircle(
            Offset(x, y),
            4,
            Paint()
              ..color = lineColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);

        final textSpan = TextSpan(children: [
          TextSpan(
              text: '${data[i]!.toStringAsFixed(1)}$unit\n',
              style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  height: 1.2)),
          TextSpan(
              text: timeLabels[i],
              style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 9)),
        ]);
        final tpPoint = TextPainter(
            text: textSpan,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr)
          ..layout();
        tpPoint.paint(
            canvas, Offset(x - tpPoint.width / 2, y - tpPoint.height - 8));

        prevX = x;
        prevY = y;
      }

      String timeLabel = i < timeLabels.length ? timeLabels[i] : "--:--";
      final tpTime = TextPainter(
          text: TextSpan(text: timeLabel, style: textStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      tpTime.paint(
          canvas, Offset(x - tpTime.width / 2, size.height - marginBottom + 5));
    }

    canvas.drawPath(path, paint);

    if (!isFirstValid && prevX != null) {
      final firstValidIndex = data.indexWhere((d) => d != null);
      final firstValidX = marginLeft + (firstValidIndex * stepX);
      final fillPath = Path.from(path);
      fillPath.lineTo(prevX, chartHeight);
      fillPath.lineTo(firstValidX, chartHeight);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              lineColor.withOpacity(0.3),
              lineColor.withOpacity(0.0)
            ]).createShader(
            Rect.fromLTWH(marginLeft, 0, chartWidth, chartHeight));
      canvas.drawPath(fillPath, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class WavePainter extends CustomPainter {
  final double progress;
  final int speed;
  final double frequency;
  final double heightFactor;
  final Color color;
  final double offset;
  final bool hasGlow;
  WavePainter(
      {required this.progress,
      required this.speed,
      required this.frequency,
      required this.heightFactor,
      required this.color,
      required this.offset,
      required this.hasGlow});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    final yBase = size.height * heightFactor;
    path.moveTo(0, size.height);
    path.lineTo(0, yBase);
    for (double x = 0; x <= size.width; x++) {
      path.lineTo(
          x,
          yBase +
              sin((x / size.width * frequency * 2 * pi) +
                      (progress * speed * 2 * pi) +
                      offset) *
                  20);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
    if (hasGlow) {
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withOpacity(0.15)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class ParticlePainter extends CustomPainter {
  final double progress;
  final Color color;
  ParticlePainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(42);
    final paint = Paint()..color = color;
    for (int i = 0; i < 25; i++) {
      double currentY = (random.nextDouble() - progress + 1.0) % 1.0;
      canvas.drawCircle(
          Offset(random.nextDouble() * size.width, currentY * size.height),
          random.nextDouble() * 2 + 1,
          paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
