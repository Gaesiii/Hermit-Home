// apps/mobile/lib/features/dashboard/presentation/dashboard_screen.dart
import 'dart:ui';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/services/auth_service.dart';
import '../../core/constants/app_constants.dart';
import 'data/device_control_repository.dart';

enum AppThemeMode { day, auto, night }

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

  bool _isSyncingData = false;

  // --- BIẾN STATE CHO TAB HỒ SƠ ---
  String _userEmail = "Đang tải...";
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
  Future<void> _loadUserProfile() async {
    try {
      final token = await _authService.getToken();
      if (token != null && token.isNotEmpty) {
        final parts = token.split('.');
        if (parts.length == 3) {
          String payload = parts[1];
          while (payload.length % 4 != 0) {
            payload += '=';
          }
          final decodedPayload = utf8.decode(base64Url.decode(payload));
          final payloadMap = jsonDecode(decodedPayload);

          final emailExtracted =
              payloadMap['email']?.toString() ?? "phuc@hermit-home.com";

          if (mounted) {
            setState(() {
              _userEmail = emailExtracted;
              _userName = emailExtracted.split('@')[0];
            });
          }
          return;
        }
      }

      final userId = await _authService.getUserId();
      if (userId != null && token != null) {
        final url = Uri.parse('${AppConstants.apiBaseUrl}/api/users/$userId');
        final response =
            await http.get(url, headers: {'Authorization': 'Bearer $token'});
        if (response.statusCode == 200) {
          final emailFromDB = jsonDecode(response.body)['email']?.toString() ??
              "phuc@hermit-home.com";
          if (mounted) {
            setState(() {
              _userEmail = emailFromDB;
              _userName = emailFromDB.split('@')[0];
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Lỗi tải thông tin: $e");
      if (mounted) {
        setState(() {
          _userEmail = "phuc@hermit-home.com";
          _userName = "Phúc";
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
        throw Exception('Xac thuc that bai.');
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
            'Khong the tai telemetry (HTTP ${teleResponse.statusCode}).');
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: accentColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accentColor.withOpacity(0.4), width: 1.5)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: accentColor.withOpacity(0.2), shape: BoxShape.circle),
            child:
                Icon(Icons.auto_awesome_rounded, color: accentColor, size: 24),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text("Trợ lý AI:",
                      style: TextStyle(
                          color: textMain.withOpacity(0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Text(
                    "Mọi thứ đều ổn định! Vi khí hậu hiện tại rất hoàn hảo cho bầy cư dân của bạn.",
                    style:
                        TextStyle(color: textMain, fontSize: 14, height: 1.4)),
              ],
            ),
          )
        ],
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
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_userEmail,
                          style: TextStyle(
                              color: textMain.withOpacity(0.7), fontSize: 14)),
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
