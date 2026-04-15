// apps/mobile/lib/features/dashboard/presentation/dashboard_screen.dart
import 'dart:ui';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String _userName = 'Đang tải...';
  String? _profileUserId;

  // --- BIẾN STATE CHO TAB LỊCH SỬ (ĐÃ ĐỔI SANG CHO PHÉP CHỨA GIÁ TRỊ NULL) ---
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
  int _currentPage = 1;
  bool _isLoadingMore = false;

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

    _historyScrollController.addListener(() {
      if (_historyScrollController.position.pixels >=
          _historyScrollController.position.maxScrollExtent + 40) {
        if (!_isLoadingMore && !_isSyncingData) {
          _syncDataFromDatabase(isLoadMore: true);
        }
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

  // Lấy User từ Token hoặc DB
  // ===========================================================================
  // HÀM BẺ KHÓA TOKEN (JWT DECODE) LẤY EMAIL TRỰC TIẾP
  // ===========================================================================
  Future<void> _loadUserProfile() async {
    try {
      final token = await _authService.getToken();
      final storedUserId = (await _authService.getUserId())?.trim();

      if (storedUserId != null && storedUserId.isNotEmpty && mounted) {
        setState(() => _profileUserId = storedUserId);
      }

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
              payloadMap['email']?.toString() ?? 'phuc@hermit-home.com';

          if (mounted) {
            setState(() {
              _userName = emailExtracted.split('@')[0];
            });
          }
          return;
        }
      }

      if (storedUserId != null && token != null) {
        final url =
            Uri.parse('${AppConstants.apiBaseUrl}/api/users/$storedUserId');
        final response =
            await http.get(url, headers: {'Authorization': 'Bearer $token'});

        if (response.statusCode == 200) {
          final emailFromDB = jsonDecode(response.body)['email']?.toString() ??
              'phuc@hermit-home.com';
          if (mounted) {
            setState(() {
              _userName = emailFromDB.split('@')[0];
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Lỗi tải thông tin: $e');
      if (mounted) {
        setState(() {
          _userName = 'Phúc';
        });
      }
    }
  }

  void _setThemeMode(AppThemeMode mode) {
    if (_currentThemeMode == mode) return;
    setState(() => _currentThemeMode = mode);
    if (_isCurrentlyDark)
      _themeController.forward();
    else
      _themeController.reverse();
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

  Future<void> _copyProfileUserId() async {
    final userId = _profileUserId?.trim();
    if (userId == null || userId.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: userId));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã copy User ID'),
        duration: Duration(milliseconds: 1200),
      ),
    );
  }

  // ===========================================================================
  // GỌI API & LỌC DATA (KÈM PADDING NULL CHO BIỂU ĐỒ)
  // ===========================================================================
  Future<void> _syncDataFromDatabase(
      {bool resetPagination = false, bool isLoadMore = false}) async {
    if (_isSyncingData || _isLoadingMore) return;

    if (isLoadMore) {
      setState(() => _isLoadingMore = true);
      _currentPage++;
    } else {
      setState(() {
        _isSyncingData = true;
        if (resetPagination) {
          _currentPage = 1;
          _tempHistory.clear();
          _humHistory.clear();
          _timeHistory.clear();
          _tableData.clear();
        }
      });
    }

    try {
      final token = await _authService.getToken();
      final userId = await _authService.getUserId();
      if (token == null || userId == null)
        throw Exception("Xác thực thất bại.");

      if (!isLoadMore) {
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
      }

      int intervalMins = 1;
      switch (_selectedInterval) {
        case '5m':
          intervalMins = 5;
          break;
        case '10m':
          intervalMins = 10;
          break;
        case '30m':
          intervalMins = 30;
          break;
        case '1h':
          intervalMins = 60;
          break;
        case '6h':
          intervalMins = 360;
          break;
      }

      int limitToFetch = 10 * intervalMins;
      if (limitToFetch > 150) limitToFetch = 150;
      if (limitToFetch < 10) limitToFetch = 10;

      final telemetryUrl = Uri.parse(
          '${AppConstants.apiBaseUrl}/api/devices/$userId/telemetry?page=$_currentPage&limit=$limitToFetch');

      final teleResponse = await http.get(telemetryUrl, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });

      if (teleResponse.statusCode == 200) {
        final decoded = jsonDecode(teleResponse.body);
        final teleList = decoded['telemetry'] as List?;

        if (teleList != null && teleList.isNotEmpty) {
          String? telemetryUserId;
          for (final record in teleList) {
            if (record is! Map) continue;
            final parsedUserId = record['userId']?.toString().trim();
            if (parsedUserId != null && parsedUserId.isNotEmpty) {
              telemetryUserId = parsedUserId;
              break;
            }
          }

          final newTableRows = <Map<String, dynamic>>[];
          DateTime? lastAddedTime;

          for (var t in teleList) {
            final rawTime = t['timestamp'] ?? t['createdAt'];
            if (rawTime == null) continue;

            try {
              final date = DateTime.parse(rawTime.toString()).toLocal();

              if (lastAddedTime == null ||
                  lastAddedTime.difference(date).inMinutes.abs() >=
                      intervalMins) {
                final tempVal = (t['temperature'] as num).toDouble();
                final humVal = (t['humidity'] as num).toDouble();

                final formattedTime =
                    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                final formattedDate =
                    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

                newTableRows.add({
                  'temp': tempVal,
                  'hum': humVal,
                  'time': formattedTime,
                  'date': formattedDate,
                });
                lastAddedTime = date;
                if (newTableRows.length >= 10) break;
              }
            } catch (e) {
              continue;
            }
          }

          if (mounted) {
            setState(() {
              if (telemetryUserId != null) {
                _profileUserId = telemetryUserId;
              }

              if (!isLoadMore) {
                final chartList =
                    newTableRows.take(6).toList().reversed.toList();

                final temps = <double?>[];
                final hums = <double?>[];
                final times = <String>[];

                for (var row in chartList) {
                  temps.add(row['temp']);
                  hums.add(row['hum']);
                  times.add(row['time']);
                }

                // THUẬT TOÁN ĐIỀN ĐỦ 6 CỘT: Nhét null và --:-- vào đầu mảng nếu thiếu
                while (temps.length < 6) {
                  temps.insert(0, null);
                  hums.insert(0, null);
                  times.insert(0, "--:--");
                }

                _tempHistory = temps;
                _humHistory = hums;
                _timeHistory = times;

                if (newTableRows.isNotEmpty) {
                  _currentTemp = newTableRows.first['temp'];
                  _currentHum = newTableRows.first['hum'];
                }
                _tableData = newTableRows;
              } else {
                _tableData.addAll(newTableRows);
              }
            });
          }
        }
      }
      if (mounted && !isLoadMore) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Đã cập nhật dữ liệu!"),
            duration: Duration(milliseconds: 800)));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Lỗi đồng bộ: $e"),
            backgroundColor: Colors.redAccent));
    } finally {
      if (mounted)
        setState(() {
          _isSyncingData = false;
          _isLoadingMore = false;
        });
    }
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 25),
                      content,
                    ],
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

        Color bgCenter =
            Color.lerp(const Color(0xFF56CCF2), const Color(0xFF002D5E), t)!;
        Color bgEdge =
            Color.lerp(const Color(0xFF2F80ED), const Color(0xFF000B18), t)!;
        Color wave1 = Color.lerp(Colors.white.withOpacity(0.5),
            const Color(0xFF006DFF).withOpacity(0.2), t)!;
        Color wave2 = Color.lerp(Colors.white.withOpacity(0.3),
            const Color(0xFF00D2FF).withOpacity(0.15), t)!;
        Color wave3 = Color.lerp(Colors.white.withOpacity(0.1),
            const Color(0xFF00F2FF).withOpacity(0.1), t)!;
        Color particleColor = Color.lerp(Colors.white.withOpacity(0.7),
            Colors.cyanAccent.withOpacity(0.25), t)!;
        Color accentColor =
            Color.lerp(const Color(0xFFFF8C00), const Color(0xFF00D2FF), t)!;

        Color glassBg = Color.lerp(
            Colors.white.withOpacity(0.25), Colors.white.withOpacity(0.08), t)!;
        Color glassBorder = Color.lerp(
            Colors.white.withOpacity(0.6), Colors.white.withOpacity(0.15), t)!;
        Color textMain = Colors.white;

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

              // ĐÃ FIX BỌT BIỂN: Đặt CustomPaint vào bên trong AnimatedBuilder để nó liên tục được vẽ lại
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
                          Text(
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
                          _buildDraggableThemeToggle(accentColor),
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
                child: _buildGlassBottomNav(glassBg, glassBorder, accentColor),
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
    // Truyền trực tiếp list có chứa null vào vẽ
    return SingleChildScrollView(
      controller: _historyScrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text("Lọc dữ liệu",
              style: TextStyle(color: textMain.withOpacity(0.8), fontSize: 14)),
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
                        color:
                            isSelected ? accentColor.withOpacity(0.3) : glassBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isSelected ? accentColor : glassBorder,
                            width: 1),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                            color: isSelected
                                ? Colors.white
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
          _buildChartCard("Biến Động Độ Ẩm", "%", const Color(0xFF00D2FF),
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
          if (!_isLoadingMore && _tableData.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text("Vuốt lên để tải thêm",
                    style: TextStyle(
                        color: textMain.withOpacity(0.4), fontSize: 12)),
              ),
            )
        ],
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
                    color: Colors.white.withOpacity(0.05),
                    border: Border(bottom: BorderSide(color: glassBorder))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        flex: 2,
                        child: Text("Thời gian",
                            style: TextStyle(
                                color: textMain.withOpacity(0.7),
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 1,
                        child: Text("Nhiệt",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: textMain.withOpacity(0.7),
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 1,
                        child: Text("Ẩm",
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: textMain.withOpacity(0.7),
                                fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: _tableData.length,
                itemBuilder: (context, index) {
                  final item = _tableData[index];
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
                                Text(item['date'],
                                    style: TextStyle(
                                        color: textMain,
                                        fontWeight: FontWeight.bold)),
                                Text(item['time'],
                                    style: TextStyle(
                                        color: textMain.withOpacity(0.5),
                                        fontSize: 11)),
                              ],
                            )),
                        Expanded(
                            flex: 1,
                            child: Text("${item['temp']}°C",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: accentColor,
                                    fontWeight: FontWeight.w600))),
                        Expanded(
                            flex: 1,
                            child: Text("${item['hum']}%",
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    color: Color(0xFF00D2FF),
                                    fontWeight: FontWeight.w600))),
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
              Text("$title ($unit)",
                  style: TextStyle(
                      color: textMain,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 25),
              SizedBox(
                height: 160,
                width: double.infinity,
                child: CustomPaint(
                  painter: LineChartPainter(
                      data: data,
                      timeLabels: times,
                      unit: unit,
                      lineColor: lineColor),
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
                        Text("Thông số hiện tại",
                            style: TextStyle(
                                color: textMain.withOpacity(0.8),
                                fontSize: 14)),
                        GestureDetector(
                          onTap: _isSyncingData
                              ? null
                              : () =>
                                  _syncDataFromDatabase(resetPagination: true),
                          child: Row(
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
                        _buildTelemetryItem(Icons.thermostat_rounded,
                            "Nhiệt Độ", tempStr, "°C", accentColor, textMain),
                        Container(
                            width: 1,
                            height: 50,
                            color: Colors.white.withOpacity(0.2)),
                        _buildTelemetryItem(Icons.water_drop_rounded, "Độ Ẩm",
                            humStr, "%", accentColor, textMain),
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
                Text("Trợ lý AI:",
                    style: TextStyle(
                        color: textMain.withOpacity(0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
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
    final profileUserId = (_profileUserId ?? '').trim();
    final hasProfileUserId = profileUserId.isNotEmpty;
    final profileIdentifier =
        hasProfileUserId ? profileUserId : 'Đang tải User ID...';
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
                    Text(displayName,
                        style: TextStyle(
                            color: textMain,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            'User ID: $profileIdentifier',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: textMain.withOpacity(0.7), fontSize: 14),
                          ),
                        ),
                        if (hasProfileUserId) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            onPressed: _copyProfileUserId,
                            icon: Icon(
                              Icons.copy_rounded,
                              size: 18,
                              color: textMain.withOpacity(0.75),
                            ),
                            tooltip: 'Copy User ID',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 30),
                    Container(height: 1, color: Colors.white.withOpacity(0.2)),
                    const SizedBox(height: 30),
                    _buildProfileOption(
                        Icons.settings_rounded, "Cài đặt hệ thống", textMain,
                        () {
                      _showGlassDialog(
                          "Cài đặt hệ thống",
                          Text(
                              "Tính năng cài đặt thông số đang được nâng cấp. Pháp sư vui lòng chờ bản cập nhật tiếp theo nhé!",
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
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
                                    color: Colors.white.withOpacity(0.8),
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
                            _buildContactRow(Icons.person_outline, "Phúc (Dev)",
                                Colors.white),
                            _buildContactRow(Icons.phone_iphone_rounded,
                                "0123 456 789", Colors.white),
                            _buildContactRow(Icons.email_outlined,
                                "phuc@hermit-home.com", Colors.white),
                            _buildContactRow(Icons.code_rounded,
                                "github.com/phuc-hermit", Colors.white),
                            _buildContactRow(Icons.work_outline_rounded,
                                "linkedin.com/in/phuc", Colors.white),
                          ]));
                    }),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.exit_to_app_rounded, color: Colors.white),
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
                  elevation: 0),
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
              child:
                  Text(title, style: TextStyle(color: textMain, fontSize: 16))),
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
        Text(text,
            style: TextStyle(
                color: textMain, fontSize: 15, fontWeight: FontWeight.w500))
      ]),
    );
  }

  // --- UI Helpers ---
  Widget _buildTelemetryItem(IconData icon, String label, String value,
      String unit, Color accentColor, Color textMain) {
    return Row(
      children: [
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: accentColor.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(icon, color: accentColor, size: 28)),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    TextStyle(color: textMain.withOpacity(0.7), fontSize: 13)),
            Row(
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
                ])
          ],
        )
      ],
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
                  Switch(
                      value: isOn,
                      onChanged: onChanged,
                      activeColor: activeColor,
                      activeTrackColor: activeColor.withOpacity(0.3),
                      inactiveThumbColor: Colors.white70,
                      inactiveTrackColor: Colors.white.withOpacity(0.1)),
                ],
              ),
              const SizedBox(height: 15),
              Text(title,
                  style: TextStyle(
                      color: textMain,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              Text(isOn ? "Đang chạy" : "Tạm nghỉ",
                  style: TextStyle(
                      color: isOn ? activeColor : textMain.withOpacity(0.5),
                      fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassBottomNav(
      Color glassBg, Color glassBorder, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 25),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(35),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
                color: glassBg,
                borderRadius: BorderRadius.circular(35),
                border: Border.all(color: glassBorder, width: 1.5)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(
                    0, Icons.show_chart_rounded, "Lịch sử", accentColor),
                _buildNavItem(1, Icons.home_rounded, "Hang chính", accentColor),
                _buildNavItem(2, Icons.person_rounded, "Hồ sơ", accentColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData icon, String label, Color accentColor) {
    bool isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
            color: isActive ? accentColor.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Icon(icon,
                color: isActive ? accentColor : Colors.white.withOpacity(0.5),
                size: 26),
            if (isActive) ...[
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: accentColor, fontWeight: FontWeight.bold))
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableThemeToggle(Color accentColor) {
    double leftPosition = 0;
    if (_currentThemeMode == AppThemeMode.auto) leftPosition = 35;
    if (_currentThemeMode == AppThemeMode.night) leftPosition = 70;

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        double dx = details.localPosition.dx;
        if (dx >= 0 && dx < 35)
          _setThemeMode(AppThemeMode.day);
        else if (dx >= 35 && dx < 70)
          _setThemeMode(AppThemeMode.auto);
        else if (dx >= 70 && dx <= 110) _setThemeMode(AppThemeMode.night);
      },
      onTapUp: (details) {
        double dx = details.localPosition.dx;
        if (dx < 35)
          _setThemeMode(AppThemeMode.day);
        else if (dx < 70)
          _setThemeMode(AppThemeMode.auto);
        else
          _setThemeMode(AppThemeMode.night);
      },
      child: Container(
        width:
            108, // FIX: Tăng từ 105 lên 108 để bù trừ cho độ dày của viền (border)
        height: 36, // Tăng nhẹ để không bị chèn ép trên/dưới
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: Colors.white.withOpacity(0.2), width: 1.5)),
        child: Stack(
          alignment: Alignment.centerLeft, // Đảm bảo mọi thứ nằm giữa
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
                _buildToggleIcon(AppThemeMode.day, Icons.wb_sunny_rounded),
                _buildToggleIcon(
                    AppThemeMode.auto, Icons.access_time_filled_rounded),
                _buildToggleIcon(AppThemeMode.night, Icons.nightlight_round),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleIcon(AppThemeMode mode, IconData icon) {
    return SizedBox(
        width: 35,
        height: 33,
        child: Icon(icon,
            color: _currentThemeMode == mode
                ? Colors.white
                : Colors.white.withOpacity(0.6),
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

  LineChartPainter(
      {required this.data,
      required this.timeLabels,
      required this.unit,
      required this.lineColor});

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
        TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10);

    // 1. VẼ TRỤC Y VÀ LƯỚI
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
            ..color = Colors.white.withOpacity(0.1)
            ..strokeWidth = 1);
    }

    // 2. VẼ BIỂU ĐỒ (ÉP ĐỦ 6 CỘT CHỨA NULL)
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
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  height: 1.2)),
          TextSpan(
              text: timeLabels[i],
              style:
                  TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 9)),
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

      // Luôn vẽ thời gian trục X cho đủ 6 cột (Kể cả khoảng trống null)
      String timeLabel = i < timeLabels.length ? timeLabels[i] : "--:--";
      final tpTime = TextPainter(
          text: TextSpan(text: timeLabel, style: textStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      tpTime.paint(
          canvas, Offset(x - tpTime.width / 2, size.height - marginBottom + 5));
    }

    canvas.drawPath(path, paint);

    // 3. ĐỔ BÓNG DƯỚI ĐƯỜNG BIỂU ĐỒ (Chỉ nếu có nét vẽ)
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
