// apps/mobile/lib/features/auth/presentation/login_screen.dart
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/auth_service.dart';

enum AppThemeMode { day, auto, night }

class LoginScreen extends StatefulWidget {
  final String? resetToken;
  final String? resetStatus;
  final String? resetUserId;
  final DateTime? resetExpiresAt;

  const LoginScreen({
    super.key,
    this.resetToken,
    this.resetStatus,
    this.resetUserId,
    this.resetExpiresAt,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // --- Controllers & Keys ---
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();
  final _forgotFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();

  final _regEmailCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();
  final _regConfirmCtrl = TextEditingController();

  final _forgotEmailCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _newPassConfirmCtrl = TextEditingController();

  final AuthService _authService = AuthService();

  // --- Animations ---
  late AnimationController _bgController;
  late AnimationController _particleController;
  late AnimationController _themeController;
  late PageController _pageController;

  late AnimationController _slowLogoController;
  late AnimationController _fastLogoController;

  bool _isLoading = false;
  int _currentPage = 1; // 0: Forgot/Reset, 1: Login, 2: Register
  AppThemeMode _currentThemeMode = AppThemeMode.auto;

  // --- BIẾN NHỚ MẬT KHẨU ---
  bool _rememberMe = false;
  final String _emailKey = 'saved_email';
  final String _passKey = 'saved_password';

  String? _currentResetToken;
  String? _resetTokenValidationError;
  String? _resetDeepLinkStatus;
  String? _resetDeepLinkUserId;
  DateTime? _resetDeepLinkExpiresAt;

  static final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  bool get _isCurrentlyDark {
    if (_currentThemeMode == AppThemeMode.night) return true;
    if (_currentThemeMode == AppThemeMode.day) return false;
    final hour = DateTime.now().hour;
    return hour < 6 || hour >= 18;
  }

  @override
  void initState() {
    super.initState();

    final incomingStatus = _normalizeResetStatus(
      widget.resetStatus,
      fallbackToken: widget.resetToken,
    );
    final incomingToken = _normalizeToken(widget.resetToken);
    final hasIncomingResetDeepLink =
        incomingStatus != null || incomingToken != null;
    int initialPage = hasIncomingResetDeepLink ? 0 : 1;
    _currentPage = initialPage;
    _pageController = PageController(initialPage: initialPage);

    _bgController =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..repeat();
    _particleController =
        AnimationController(vsync: this, duration: const Duration(seconds: 15))
          ..repeat();
    _slowLogoController =
        AnimationController(vsync: this, duration: const Duration(seconds: 20))
          ..repeat();
    _fastLogoController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();

    _themeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
      value: _isCurrentlyDark ? 1.0 : 0.0,
    );

    _loadSavedCredentials();

    if (hasIncomingResetDeepLink) {
      _consumeIncomingResetDeepLink(
        status: incomingStatus,
        token: incomingToken,
        userId: widget.resetUserId,
        expiresAt: widget.resetExpiresAt,
        showPopup: false,
      );
    }
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newStatus = _normalizeResetStatus(
      widget.resetStatus,
      fallbackToken: widget.resetToken,
    );
    final oldStatus = _normalizeResetStatus(
      oldWidget.resetStatus,
      fallbackToken: oldWidget.resetToken,
    );
    final newToken = _normalizeToken(widget.resetToken);
    final oldToken = _normalizeToken(oldWidget.resetToken);
    final hasNewDeepLink = newStatus != null || newToken != null;
    final hasChanged = newStatus != oldStatus ||
        newToken != oldToken ||
        widget.resetUserId != oldWidget.resetUserId ||
        widget.resetExpiresAt != oldWidget.resetExpiresAt;

    if (hasNewDeepLink && hasChanged) {
      _goToPage(0);
      _consumeIncomingResetDeepLink(
        status: newStatus,
        token: newToken,
        userId: widget.resetUserId,
        expiresAt: widget.resetExpiresAt,
      );
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _particleController.dispose();
    _themeController.dispose();
    _pageController.dispose();
    _slowLogoController.dispose();
    _fastLogoController.dispose();

    _loginEmailCtrl.dispose();
    _loginPassCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPassCtrl.dispose();
    _regConfirmCtrl.dispose();
    _forgotEmailCtrl.dispose();
    _newPassCtrl.dispose();
    _newPassConfirmCtrl.dispose();
    super.dispose();
  }

  // =========================================================
  // LOGIC NHỚ MẬT KHẨU
  // =========================================================
  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString(_emailKey);
    final savedPass = prefs.getString(_passKey);

    if (savedEmail != null && savedPass != null) {
      if (mounted) {
        setState(() {
          _loginEmailCtrl.text = savedEmail;
          _loginPassCtrl.text = savedPass;
          _rememberMe = true;
        });
      }
    }
  }

  Future<void> _saveOrClearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString(_emailKey, _loginEmailCtrl.text.trim());
      await prefs.setString(_passKey, _loginPassCtrl.text);
    } else {
      await prefs.remove(_emailKey);
      await prefs.remove(_passKey);
    }
  }

  String? _normalizeToken(String? token) {
    if (token == null) return null;
    final normalized = token.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _normalizeResetStatus(String? status, {String? fallbackToken}) {
    final normalized = status?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return _normalizeToken(fallbackToken) == null ? null : 'valid';
    }

    if (normalized == 'valid' && _normalizeToken(fallbackToken) == null) {
      return 'missing_token';
    }

    return normalized;
  }

  String _messageForResetStatus(String status) {
    switch (status) {
      case 'valid':
        return 'Tín hiệu tìm vỏ hợp lệ. Hãy rèn mật mã mới!';
      case 'missing_token':
        return 'Tín hiệu tìm vỏ bị rớt mất token rồi.';
      case 'invalid_token':
        return 'Tín hiệu tìm vỏ này hỏng rồi.';
      case 'expired_token':
        return 'Tín hiệu tìm vỏ đã bay màu theo sóng biển (hết hạn).';
      case 'used_token':
        return 'Tín hiệu này đã được dùng để đúc vỏ trước đó rồi.';
      case 'user_not_found':
        return 'Không tìm thấy ốc mượn hồn nào ở tọa độ này.';
      case 'server_error':
        return 'Bão biển làm mất kết nối máy chủ, thử lại sau nhé.';
      default:
        return 'Tình trạng tín hiệu không xác định được.';
    }
  }

  String _formatResetExpiresAt(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  bool _isValidEmail(String email) => _emailRe.hasMatch(email.trim());

  void _consumeIncomingResetDeepLink({
    required String? status,
    required String? token,
    String? userId,
    DateTime? expiresAt,
    bool showPopup = true,
  }) {
    final normalizedToken = _normalizeToken(token);
    final normalizedStatus = _normalizeResetStatus(
      status,
      fallbackToken: normalizedToken,
    );

    if (normalizedStatus == null) {
      return;
    }

    final isValidStatus =
        normalizedStatus == 'valid' && normalizedToken != null;
    final statusMessage = _messageForResetStatus(normalizedStatus);
    final normalizedUserId = userId?.trim();

    setState(() {
      _resetDeepLinkStatus = normalizedStatus;
      _resetDeepLinkUserId =
          (normalizedUserId == null || normalizedUserId.isEmpty)
              ? null
              : normalizedUserId;
      _resetDeepLinkExpiresAt = expiresAt;
      _currentResetToken = isValidStatus ? normalizedToken : null;
      _resetTokenValidationError = isValidStatus ? null : statusMessage;
    });

    if (!showPopup) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(statusMessage),
            backgroundColor: isValidStatus ? Colors.green : Colors.redAccent,
          ),
        );
      }
    });
  }

  void _onPageChanged(int index) {
    FocusScope.of(context).unfocus();
    setState(() => _currentPage = index);
  }

  void _goToPage(int pageIndex) {
    FocusScope.of(context).unfocus();
    _pageController.animateToPage(pageIndex,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic);
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

  // =========================================================
  // API CALLS
  // =========================================================
  Future<void> _submitLogin() async {
    if (_isLoading || !(_loginFormKey.currentState?.validate() ?? false))
      return;
    setState(() => _isLoading = true);

    final result = await _authService.login(
        email: _loginEmailCtrl.text.trim(), password: _loginPassCtrl.text);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      await _saveOrClearCredentials();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      _showError('Mật mã khép vỏ trật lất rồi!');
    }
  }

  Future<void> _submitRegister() async {
    if (_isLoading || !(_registerFormKey.currentState?.validate() ?? false))
      return;
    if (_regPassCtrl.text != _regConfirmCtrl.text) {
      _showError('Mật mã nhắc lại lệch tông rồi!');
      return;
    }
    setState(() => _isLoading = true);

    final result = await _authService.register(
        email: _regEmailCtrl.text.trim(), password: _regPassCtrl.text);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      _showError(result.errorMessage ?? 'Săn vỏ thất bại, sóng đánh tan tành!');
    }
  }

  Future<void> _submitForgotPassword() async {
    if (_isLoading || !(_forgotFormKey.currentState?.validate() ?? false))
      return;

    final email = _forgotEmailCtrl.text.trim();
    if (!_isValidEmail(email)) {
      _showError('Tọa độ bãi cát (Email) sai cú pháp rồi.');
      return;
    }

    setState(() {
      _isLoading = true;
      _resetTokenValidationError = null;
      _resetDeepLinkStatus = null;
      _resetDeepLinkUserId = null;
      _resetDeepLinkExpiresAt = null;
    });
    final result = await _authService.forgotPassword(email: email);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tín hiệu tìm vỏ đã được thả trôi chai vào mail bạn.'),
          backgroundColor: Colors.green,
        ),
      );
      _goToPage(1);
      return;
    }

    _showError(result.errorMessage ?? 'Gửi tín hiệu xịt rồi, sóng yếu quá.');
  }

  Future<void> _submitResetPassword() async {
    if (_isLoading || !(_resetFormKey.currentState?.validate() ?? false))
      return;

    if (_currentResetToken == null) {
      _showError('Tín hiệu tìm vỏ hỏng hoặc đã chìm mất.');
      return;
    }

    if (_newPassCtrl.text.length < 8) {
      _showError('Mật mã khép vỏ phải dày ít nhất 8 lớp (ký tự).');
      return;
    }

    if (_newPassCtrl.text != _newPassConfirmCtrl.text) {
      _showError('Hai lớp mật mã vỏ gõ chưa khớp nhau.');
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.resetPassword(
      token: _currentResetToken!,
      newPassword: _newPassCtrl.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đúc lại mật mã thành công! Về hang thôi.'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _currentResetToken = null;
        _resetTokenValidationError = null;
        _resetDeepLinkStatus = null;
        _resetDeepLinkUserId = null;
        _resetDeepLinkExpiresAt = null;
      });
      _newPassCtrl.clear();
      _newPassConfirmCtrl.clear();
      _goToPage(1);
      return;
    }

    final errorMessage =
        result.errorMessage ?? 'Tín hiệu tìm vỏ hỏng hoặc đã chìm mất.';
    if (errorMessage.toLowerCase().contains('invalid') ||
        errorMessage.toLowerCase().contains('expired') ||
        errorMessage.toLowerCase().contains('used')) {
      setState(() {
        _currentResetToken = null;
        _resetTokenValidationError = errorMessage;
        _resetDeepLinkStatus = null;
        _resetDeepLinkUserId = null;
        _resetDeepLinkExpiresAt = null;
      });
    }

    _showError(errorMessage);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent));
  }

  String _getHeaderText() {
    if (_currentPage == 0) {
      return _currentResetToken == null
          ? 'Lạc Mất Đường Vào Hang?'
          : 'Đúc Lại Chìa Khóa Vỏ';
    } else if (_currentPage == 1) {
      return 'Chào Mừng Về Vỏ!';
    }
    return 'Tìm Vỏ Mới';
  }

  @override
  Widget build(BuildContext context) {
    // Logic responsive cho kích thước màn hình
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 650;
    final double logoSize = isSmallScreen ? 70 : 100;
    final double spacing = isSmallScreen ? 10 : 20;

    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, child) {
        double t = _themeController.value;

        // BẢNG MÀU ĐÃ CẬP NHẬT TƯƠNG PHẢN ĐỘNG
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

        Color textMain = Color.lerp(const Color(0xFF001E36), Colors.white, t)!;

        Color glassBg = Color.lerp(
            Colors.white.withOpacity(0.55), Colors.white.withOpacity(0.08), t)!;
        Color glassBorder = Color.lerp(
            Colors.white.withOpacity(0.9), Colors.white.withOpacity(0.15), t)!;

        Color inputFill = Color.lerp(
            Colors.white.withOpacity(0.65), Colors.white.withOpacity(0.1), t)!;
        Color inputHint = Color.lerp(const Color(0xFF003366).withOpacity(0.6),
            Colors.white.withOpacity(0.5), t)!;
        Color inputFocusedBorder =
            Color.lerp(accentColor, const Color(0xFF00D2FF), t)!;

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
                    child: Container()),
              ),
              AnimatedBuilder(
                animation: _bgController,
                builder: (context, child) {
                  bool isDark = t > 0.5;
                  return Stack(
                    children: [
                      _buildWave(
                          speed: 1,
                          frequency: 1.0,
                          height: 0.65,
                          color: wave1,
                          offset: 0.0,
                          hasGlow: isDark),
                      _buildWave(
                          speed: -1,
                          frequency: 1.3,
                          height: 0.75,
                          color: wave2,
                          offset: pi,
                          hasGlow: isDark),
                      _buildWave(
                          speed: 2,
                          frequency: 0.8,
                          height: 0.85,
                          color: wave3,
                          offset: pi / 2,
                          hasGlow: isDark),
                    ],
                  );
                },
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: Align(
                        alignment: Alignment.topRight,
                        child:
                            _buildDraggableThemeToggle(accentColor, textMain),
                      ),
                    ),
                    //
                    Container(
                      width: logoSize,
                      height: logoSize,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: accentColor, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor
                                  .withOpacity(0.4), // Phát sáng viền ngoài
                              blurRadius: 20,
                              spreadRadius: 2,
                            )
                          ]),
                      child: ClipOval(
                        child: Image.asset(
                          _isCurrentlyDark
                              ? 'assets/images/download.png'
                              : 'assets/images/download1.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    SizedBox(height: spacing),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: Text(
                            _getHeaderText(),
                            key: ValueKey<String>(_getHeaderText()),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: textMain,
                              letterSpacing: 1.5,
                              shadows: [
                                Shadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 5)
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Hệ thống quản lý cư dân Hermit-Home',
                          style: TextStyle(
                              color: textMain.withOpacity(0.8),
                              fontSize: 14,
                              letterSpacing: 1.1),
                        ),
                      ),
                    ),
                    SizedBox(height: spacing),
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const BouncingScrollPhysics(),
                        onPageChanged: _onPageChanged,
                        children: [
                          _buildForgotOrResetForm(
                            glassBg: glassBg,
                            glassBorder: glassBorder,
                            accentColor: accentColor,
                            textMain: textMain,
                            inputFill: inputFill,
                            inputHint: inputHint,
                            focusedBorderColor: inputFocusedBorder,
                          ),
                          _buildLoginForm(
                            glassBg: glassBg,
                            glassBorder: glassBorder,
                            accentColor: accentColor,
                            textMain: textMain,
                            inputFill: inputFill,
                            inputHint: inputHint,
                            focusedBorderColor: inputFocusedBorder,
                          ),
                          _buildRegisterForm(
                            glassBg: glassBg,
                            glassBorder: glassBorder,
                            accentColor: accentColor,
                            textMain: textMain,
                            inputFill: inputFill,
                            inputHint: inputHint,
                            focusedBorderColor: inputFocusedBorder,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // CÁC THÀNH PHẦN UI RIÊNG BIỆT CHO TỪNG TRANG:

  Widget _buildForgotOrResetForm({
    required Color glassBg,
    required Color glassBorder,
    required Color accentColor,
    required Color textMain,
    required Color inputFill,
    required Color inputHint,
    required Color focusedBorderColor,
  }) {
    final isResetMode = _currentResetToken != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          _buildGlassContainer(
            glassBg: glassBg,
            glassBorder: glassBorder,
            child: Form(
              key: isResetMode ? _resetFormKey : _forgotFormKey,
              child: Column(
                children: [
                  if (!isResetMode) ...[
                    Text(
                      'Nhập tọa độ hang để nhận thư dạt bờ tìm lại vỏ nhé!',
                      style: TextStyle(color: textMain, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    if (_resetTokenValidationError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _resetTokenValidationError!,
                        style: TextStyle(
                          color: Colors.redAccent.withOpacity(0.95),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _forgotEmailCtrl,
                      label: 'Tọa độ vỏ (Email)',
                      icon: Icons.waves_rounded,
                      accentColor: accentColor,
                      textMain: textMain,
                      inputFill: inputFill,
                      inputHint: inputHint,
                      focusedBorderColor: focusedBorderColor,
                    ),
                  ] else ...[
                    Text(
                      'Đã tìm thấy hang! Hãy rèn một đoạn mật mã vỏ mới cứng cáp hơn.',
                      style: TextStyle(color: textMain, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    if (_resetDeepLinkStatus != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Trạng thái sóng: $_resetDeepLinkStatus',
                        style: TextStyle(
                          color: textMain.withOpacity(0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _newPassCtrl,
                      label: 'Mật mã vỏ mới',
                      icon: Icons.lock_reset,
                      obscureText: true,
                      accentColor: accentColor,
                      textMain: textMain,
                      inputFill: inputFill,
                      inputHint: inputHint,
                      focusedBorderColor: focusedBorderColor,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _newPassConfirmCtrl,
                      label: 'Khắc lại mật mã vỏ mới',
                      icon: Icons.verified_user_outlined,
                      obscureText: true,
                      accentColor: accentColor,
                      textMain: textMain,
                      inputFill: inputFill,
                      inputHint: inputHint,
                      focusedBorderColor: focusedBorderColor,
                    ),
                  ],
                  const SizedBox(height: 24),
                  _buildSubmitBtn(
                    label: isResetMode ? 'ĐÚC LẠI VỎ' : 'GỬI TÍN HIỆU TÌM VỎ',
                    onPressed: isResetMode
                        ? _submitResetPassword
                        : _submitForgotPassword,
                    accentColor: accentColor,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          _buildNavText(
            text1: 'Nhớ ra đường chui vào vỏ rồi? ',
            text2: 'Về hang thôi',
            onTap: () => _goToPage(1),
            textMain: textMain,
            accentColor: accentColor,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLoginForm({
    required Color glassBg,
    required Color glassBorder,
    required Color accentColor,
    required Color textMain,
    required Color inputFill,
    required Color inputHint,
    required Color focusedBorderColor,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          _buildGlassContainer(
            glassBg: glassBg,
            glassBorder: glassBorder,
            child: Form(
              key: _loginFormKey,
              child: Column(
                children: [
                  _buildField(
                    controller: _loginEmailCtrl,
                    label: 'Tọa độ bãi cát (Email)',
                    icon: Icons.waves_rounded,
                    accentColor: accentColor,
                    textMain: textMain,
                    inputFill: inputFill,
                    inputHint: inputHint,
                    focusedBorderColor: focusedBorderColor,
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _loginPassCtrl,
                    label: 'Mật khẩu khép vỏ',
                    icon: Icons.security_rounded,
                    obscureText: true,
                    accentColor: accentColor,
                    textMain: textMain,
                    inputFill: inputFill,
                    inputHint: inputHint,
                    focusedBorderColor: focusedBorderColor,
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () =>
                              setState(() => _rememberMe = !_rememberMe),
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: _rememberMe
                                      ? accentColor.withOpacity(0.8)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: _rememberMe
                                          ? accentColor
                                          : textMain.withOpacity(
                                              0.5), // Sửa tương phản nút tick
                                      width: 1.5),
                                ),
                                child: _rememberMe
                                    ? const Icon(Icons.check_rounded,
                                        size: 14,
                                        color: Colors
                                            .white) // Icon tick luôn trắng
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Text("Đánh dấu mùi vỏ",
                                  style: TextStyle(
                                      color: textMain.withOpacity(0.8),
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        TextButton(
                          onPressed: () => _goToPage(0),
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          child: Text("Sóng cuốn mất chìa?",
                              style: TextStyle(
                                  color: accentColor,
                                  fontSize: 13,
                                  decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSubmitBtn(
                      label: 'CỤP MẮT VÀ CHUI VÀO',
                      onPressed: _submitLogin,
                      accentColor: accentColor),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          _buildNavText(
              text1: "Đang ở trần? ",
              text2: "Đi lùng vỏ mới",
              onTap: () => _goToPage(2),
              textMain: textMain,
              accentColor: accentColor),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildRegisterForm({
    required Color glassBg,
    required Color glassBorder,
    required Color accentColor,
    required Color textMain,
    required Color inputFill,
    required Color inputHint,
    required Color focusedBorderColor,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          _buildGlassContainer(
            glassBg: glassBg,
            glassBorder: glassBorder,
            child: Form(
              key: _registerFormKey,
              child: Column(
                children: [
                  _buildField(
                    controller: _regEmailCtrl,
                    label: 'Tọa độ bãi cát (Email)',
                    icon: Icons.waves_rounded,
                    accentColor: accentColor,
                    textMain: textMain,
                    inputFill: inputFill,
                    inputHint: inputHint,
                    focusedBorderColor: focusedBorderColor,
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _regPassCtrl,
                    label: 'Mã chống cua hoàng đế',
                    icon: Icons.security_rounded,
                    obscureText: true,
                    accentColor: accentColor,
                    textMain: textMain,
                    inputFill: inputFill,
                    inputHint: inputHint,
                    focusedBorderColor: focusedBorderColor,
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _regConfirmCtrl,
                    label: 'Khắc lại mã chống cua',
                    icon: Icons.verified_user_outlined,
                    obscureText: true,
                    accentColor: accentColor,
                    textMain: textMain,
                    inputFill: inputFill,
                    inputHint: inputHint,
                    focusedBorderColor: focusedBorderColor,
                  ),
                  const SizedBox(height: 24),
                  _buildSubmitBtn(
                      label: 'CHIẾM VỎ NGAY',
                      onPressed: _submitRegister,
                      accentColor: accentColor),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          _buildNavText(
              text1: "Có vỏ xịn rồi? ",
              text2: "Về hang ngủ thôi!",
              onTap: () => _goToPage(1),
              textMain: textMain,
              accentColor: accentColor),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // UTILITY WIDGETS
  Widget _buildGlassContainer(
      {required Color glassBg,
      required Color glassBorder,
      required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(35),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: glassBg,
            borderRadius: BorderRadius.circular(35),
            border: Border.all(color: glassBorder, width: 1.5),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSubmitBtn(
      {required String label,
      required VoidCallback onPressed,
      required Color accentColor}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 55),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white, // Chữ trên nút nhấn vẫn là màu trắng
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
          child: _isLoading
              ? RotationTransition(
                  turns: _fastLogoController,
                  child:
                      const AlchemistVortexLogo(size: 28, color: Colors.white),
                )
              : Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2),
                ),
        ),
      ),
    );
  }

  Widget _buildNavText(
      {required String text1,
      required String text2,
      required VoidCallback onTap,
      required Color textMain,
      required Color accentColor}) {
    return TextButton(
      onPressed: onTap,
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          text: text1,
          style: TextStyle(color: textMain.withOpacity(0.8), fontSize: 15),
          children: [
            TextSpan(
              text: text2,
              style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline),
            ),
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
        width: 108,
        height: 36,
        decoration: BoxDecoration(
          color: textMain.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: textMain.withOpacity(0.2), width: 1.5),
        ),
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
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
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
      child: Icon(
        icon,
        color: _currentThemeMode == mode
            ? Colors
                .white // Icon đang chọn (nằm đè lên màu cam/xanh cyan) luôn hiển thị màu Trắng
            : textMain.withOpacity(
                0.6), // Các icon chưa được chọn tự tương phản với nền
        size: 16,
      ),
    );
  }

  Widget _buildWave(
      {required int speed,
      required double frequency,
      required double height,
      required Color color,
      required double offset,
      required bool hasGlow}) {
    return CustomPaint(
      painter: WavePainter(
        progress: _bgController.value,
        speed: speed,
        frequency: frequency,
        heightFactor: height,
        color: color,
        offset: offset,
        hasGlow: hasGlow,
      ),
      child: Container(),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    required Color accentColor,
    required Color textMain,
    required Color inputFill,
    required Color inputHint,
    required Color focusedBorderColor,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: TextStyle(color: textMain, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: inputHint, fontSize: 14),
        prefixIcon: Icon(icon,
            color: textMain.withOpacity(0.8),
            size: 20), // Chỉnh tương phản cho icon
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: textMain.withOpacity(0.3), width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: textMain.withOpacity(0.3), width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: focusedBorderColor, width: 2.0),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      ),
      validator: (value) => (value == null || value.isEmpty)
          ? 'Không được để trống đâu cư dân ơi!'
          : null,
    );
  }
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
      double y = yBase +
          sin((x / size.width * frequency * 2 * pi) +
                  (progress * speed * 2 * pi) +
                  offset) *
              20;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);

    if (hasGlow) {
      final glowPaint = Paint()
        ..color = Colors.white.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawPath(path, glowPaint);
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
      double startX = random.nextDouble();
      double startY = random.nextDouble();
      double currentY = (startY - progress + 1.0) % 1.0;
      canvas.drawCircle(Offset(startX * size.width, currentY * size.height),
          random.nextDouble() * 2 + 1, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class AlchemistVortexLogo extends StatelessWidget {
  final double size;
  final Color color;
  const AlchemistVortexLogo({super.key, this.size = 100, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: CustomPaint(painter: _AlchemistVortexPainter(color: color)),
    );
  }
}

class _AlchemistVortexPainter extends CustomPainter {
  final Color color;
  _AlchemistVortexPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    paint.color = color;
    paint.strokeWidth = 2.5;
    for (double i = 0; i < 360; i += 60) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius * 0.7),
          i * pi / 180, pi / 4, false, paint);
    }
    paint.style = PaintingStyle.fill;
    paint.color = Colors.white;
    canvas.drawCircle(center, radius * 0.12, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
