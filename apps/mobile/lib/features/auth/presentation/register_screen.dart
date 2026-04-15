// apps/mobile/lib/features/auth/presentation/register_screen.dart
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/services/auth_service.dart';
import '../auth_routes.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final AuthService _authService = AuthService();
  late AnimationController _bgController;
  late AnimationController _particleController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _particleController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading || !(_formKey.currentState?.validate() ?? false)) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mật mã nhắc lại không khớp Thầy ơi!')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final result = await _authService.register(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Dựng vỏ thất bại rồi!'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000B18),
      body: Stack(
        children: [
          // 1. Nền Deep Sea Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.bottomRight,
                radius: 1.5,
                colors: [Color(0xFF002D5E), Color(0xFF000B18)],
              ),
            ),
          ),

          // 2. Hạt sáng lơ lửng (Plankton particles)
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, child) => CustomPaint(
              painter: ParticlePainter(progress: _particleController.value),
              child: Container(),
            ),
          ),

          // 3. Sóng Bioluminescent chuyển động
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return Stack(
                children: [
                  _buildWave(
                      0.4, 0.65, const Color(0xFF006DFF).withOpacity(0.2), 0),
                  _buildWave(0.3, 0.75,
                      const Color(0xFF00D2FF).withOpacity(0.15), 1.5),
                ],
              );
            },
          ),

          // 4. Nội dung UI
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                child: Column(
                  children: [
                    const AlchemistVortexLogo(size: 100),
                    const SizedBox(height: 24),
                    const Text(
                      'Dựng Vỏ Mới',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Gia nhập bầy Hermit-Home ngay hôm nay',
                      style: TextStyle(
                        color: Colors.cyanAccent.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Khung Form Đăng Ký (Glassmorphism)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(35),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.all(25),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(35),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                _buildShellField(
                                  controller: _emailController,
                                  label: 'Địa chỉ hang (Email)',
                                  icon: Icons.alternate_email_rounded,
                                ),
                                const SizedBox(height: 16),
                                _buildShellField(
                                  controller: _passwordController,
                                  label: 'Mật mã phòng thủ',
                                  icon: Icons.security_rounded,
                                  obscureText: true,
                                ),
                                const SizedBox(height: 16),
                                _buildShellField(
                                  controller: _confirmPasswordController,
                                  label: 'Nhắc lại mật mã',
                                  icon: Icons.verified_user_outlined,
                                  obscureText: true,
                                ),
                                const SizedBox(height: 32),
                                SizedBox(
                                  width: double.infinity,
                                  height: 55,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00D2FF),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: _isLoading
                                        ? const CircularProgressIndicator(
                                            color: Colors.white)
                                        : const Text(
                                            'XÂY HANG NGAY',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 2,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: RichText(
                        text: TextSpan(
                          text: "Đã có vỏ rồi? ",
                          style:
                              TextStyle(color: Colors.white.withOpacity(0.7)),
                          children: const [
                            TextSpan(
                              text: 'Về hang thôi!',
                              style: TextStyle(
                                color: Colors.cyanAccent,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWave(
      double speed, double heightMultiplier, Color color, double offset) {
    return CustomPaint(
      painter: WavePainter(
        progress: _bgController.value * speed + offset,
        heightFactor: heightMultiplier,
        color: color,
      ),
      child: Container(),
    );
  }

  Widget _buildShellField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
        prefixIcon:
            Icon(icon, color: Colors.cyanAccent.withOpacity(0.6), size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.03),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.cyanAccent, width: 1),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      ),
      validator: (value) =>
          (value == null || value.isEmpty) ? 'Trống rồi Thầy ơi!' : null,
    );
  }
}

// --- CÁC PAINTER NGHỆ THUẬT (REUSE) ---

class WavePainter extends CustomPainter {
  final double progress;
  final double heightFactor;
  final Color color;
  WavePainter(
      {required this.progress,
      required this.heightFactor,
      required this.color});

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
      double y =
          yBase + sin((x / size.width * 2 * pi) + (progress * 2 * pi)) * 20;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);

    final glowPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(path, glowPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class ParticlePainter extends CustomPainter {
  final double progress;
  ParticlePainter({required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(42);
    final paint = Paint()..color = Colors.cyanAccent.withOpacity(0.25);
    for (int i = 0; i < 25; i++) {
      double x = random.nextDouble() * size.width;
      double y =
          (random.nextDouble() * size.height + (progress * 80)) % size.height;
      canvas.drawCircle(Offset(x, y), random.nextDouble() * 2, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class AlchemistVortexLogo extends StatelessWidget {
  final double size;
  const AlchemistVortexLogo({super.key, this.size = 100});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.cyanAccent.withOpacity(0.15), blurRadius: 25)
        ],
      ),
      child: CustomPaint(painter: _AlchemistVortexPainter()),
    );
  }
}

class _AlchemistVortexPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    paint.color = Colors.cyanAccent;
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
