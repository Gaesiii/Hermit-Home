// apps/mobile/lib/features/dashboard/presentation/dashboard_screen.dart
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/services/auth_service.dart';

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

  AppThemeMode _currentThemeMode = AppThemeMode.auto;
  int _currentIndex = 1;

  // --- Trạng thái thiết bị ---
  bool isLightOn = true;
  bool isHeatOn = false;
  bool isMistOn = false;

  final AuthService _authService = AuthService();

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
      value: _isCurrentlyDark ? 1.0 : 0.0,
    );
  }

  @override
  void dispose() {
    _bgController.dispose();
    _particleController.dispose();
    _themeController.dispose();
    _pageController.dispose();
    super.dispose();
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
              CustomPaint(
                  painter: ParticlePainter(
                      progress: _particleController.value,
                      color: particleColor),
                  child: Container()),
              Stack(
                children: [
                  _buildWave(1, 1.0, 0.65, wave1, 0.0, t > 0.5),
                  _buildWave(-1, 1.3, 0.75, wave2, pi, t > 0.5),
                  _buildWave(2, 0.8, 0.85, wave3, pi / 2, t > 0.5),
                ],
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
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          _buildChartCard("Biến Động Nhiệt Độ (°C)", accentColor, glassBg,
              glassBorder, textMain, [26.0, 27.5, 28.5, 28.0, 27.2, 28.5]),
          const SizedBox(height: 20),
          _buildChartCard(
              "Biến Động Độ Ẩm (%)",
              const Color(0xFF00D2FF),
              glassBg,
              glassBorder,
              textMain,
              [75.0, 78.0, 80.0, 85.0, 82.0, 81.0]),
        ],
      ),
    );
  }

  Widget _buildChartCard(String title, Color lineColor, Color glassBg,
      Color glassBorder, Color textMain, List<double> data) {
    return ClipRRect(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: textMain,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              SizedBox(
                height: 120,
                width: double.infinity,
                child: CustomPaint(
                  painter: LineChartPainter(data: data, lineColor: lineColor),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Sáng",
                      style: TextStyle(
                          color: textMain.withOpacity(0.6), fontSize: 12)),
                  Text("Bây giờ",
                      style: TextStyle(
                          color: textMain.withOpacity(0.6), fontSize: 12)),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  // --- TAB 1: HANG CHÍNH (HOME) ---
  Widget _buildHomeTab(
      Color glassBg, Color glassBorder, Color textMain, Color accentColor) {
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
                        _buildTelemetryItem(Icons.thermostat_rounded,
                            "Nhiệt Độ", "28.5", "°C", accentColor, textMain),
                        Container(
                            width: 1,
                            height: 50,
                            color: Colors.white.withOpacity(0.2)),
                        _buildTelemetryItem(Icons.water_drop_rounded, "Độ Ẩm",
                            "82", "%", accentColor, textMain),
                      ],
                    ),
                    const SizedBox(height: 25),
                    Container(height: 1, color: Colors.white.withOpacity(0.2)),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildSmallTelemetry(
                            Icons.grass_rounded, "Đất", "75%", textMain),
                        _buildSmallTelemetry(
                            Icons.light_mode_rounded, "UV", "Mức 2", textMain),
                        _buildSmallTelemetry(
                            Icons.air_rounded, "Khí", "Sạch", textMain),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Text("Thiết Bị Điện",
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
                      (val) => setState(() => isLightOn = val),
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
                      (val) => setState(() => isHeatOn = val),
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
                      (val) => setState(() => isMistOn = val),
                      glassBg,
                      glassBorder,
                      const Color(0xFF4FC3F7),
                      textMain)),
              const SizedBox(width: 15),
              Expanded(
                  child: _buildDeviceCard(
                      "Quạt Gió",
                      Icons.mode_fan_off_rounded,
                      false,
                      (val) {},
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

  // --- TAB 2: HỒ SƠ (PROFILE) ---
  Widget _buildProfileTab(
      Color glassBg, Color glassBorder, Color textMain, Color accentColor) {
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
                    Text("Tộc Trưởng",
                        style: TextStyle(
                            color: textMain,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text("admin@hermit-home.com",
                        style: TextStyle(
                            color: textMain.withOpacity(0.7), fontSize: 14)),
                    const SizedBox(height: 30),
                    Container(height: 1, color: Colors.white.withOpacity(0.2)),
                    const SizedBox(height: 30),

                    // Các tuỳ chọn cài đặt
                    _buildProfileOption(
                        Icons.settings_rounded, "Cài đặt hệ thống", textMain),
                    const SizedBox(height: 15),
                    _buildProfileOption(Icons.notifications_rounded,
                        "Thông báo cảnh báo", textMain),
                    const SizedBox(height: 15),
                    _buildProfileOption(
                        Icons.help_outline_rounded, "Hỗ trợ cư dân", textMain),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),

          // Nút Đăng xuất
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
                elevation: 0,
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildProfileOption(IconData icon, String title, Color textMain) {
    return Row(
      children: [
        Icon(icon, color: textMain.withOpacity(0.8), size: 24),
        const SizedBox(width: 15),
        Expanded(
            child:
                Text(title, style: TextStyle(color: textMain, fontSize: 16))),
        Icon(Icons.chevron_right_rounded, color: textMain.withOpacity(0.5)),
      ],
    );
  }

  // --- Các Widget con của Tab Chính ---
  Widget _buildTelemetryItem(IconData icon, String label, String value,
      String unit, Color accentColor, Color textMain) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: accentColor.withOpacity(0.2), shape: BoxShape.circle),
          child: Icon(icon, color: accentColor, size: 28),
        ),
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
                        color: textMain.withOpacity(0.7), fontSize: 16)),
              ],
            )
          ],
        )
      ],
    );
  }

  Widget _buildSmallTelemetry(
      IconData icon, String label, String value, Color textMain) {
    return Column(
      children: [
        Icon(icon, color: textMain.withOpacity(0.8), size: 24),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(color: textMain.withOpacity(0.6), fontSize: 12)),
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
                width: 1.5),
          ),
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
                    inactiveTrackColor: Colors.white.withOpacity(0.1),
                  ),
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

  // --- BOTTOM NAV BAR ---
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
                _buildNavItem(0, Icons.history_rounded, "Lịch sử", accentColor),
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
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isActive ? accentColor : Colors.white.withOpacity(0.5),
                size: 26),
            if (isActive) ...[
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: accentColor, fontWeight: FontWeight.bold)),
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
        else if (dx >= 70 && dx <= 105) _setThemeMode(AppThemeMode.night);
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
        width: 105,
        height: 34,
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2))),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              left: leftPosition,
              child: Container(
                  width: 35,
                  height: 34,
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
        height: 34,
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

// --- CUSTOM PAINTER BIỂU ĐỒ LỊCH SỬ ---
class LineChartPainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;

  LineChartPainter({required this.data, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxData = data.reduce(max);
    final minData = data.reduce(min);
    final range = maxData - minData == 0 ? 1 : maxData - minData;

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      // Chuẩn hóa Y
      final normalizedY = 1 - ((data[i] - minData) / range);
      // Giới hạn chiều cao biểu đồ để không chạm nóc hoặc đáy (đệm 20%)
      final y = normalizedY * (size.height * 0.6) + (size.height * 0.2);
      final x = i * stepX;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        // Làm mượt đường cong (Cubic Bezier)
        final prevX = (i - 1) * stepX;
        final prevNormalizedY = 1 - ((data[i - 1] - minData) / range);
        final prevY =
            prevNormalizedY * (size.height * 0.6) + (size.height * 0.2);

        final controlPointX = prevX + (x - prevX) / 2;
        path.cubicTo(controlPointX, prevY, controlPointX, y, x, y);
      }

      // Vẽ các điểm neo
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
    }

    canvas.drawPath(path, paint);

    // Đổ bóng dưới đường biểu đồ
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lineColor.withOpacity(0.3), lineColor.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// --- PAINTERS TỪ TRANG LOGIN BÊ SANG ---
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
