import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/services/auth_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_routes.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/user_api_test_screen.dart';
// Lưu ý kiểm tra lại đường dẫn import này cho đúng với cấu trúc thư mục của Tộc Trưởng:
import 'features/dashboard/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const HermitHomeApp());
}

class HermitHomeApp extends StatelessWidget {
  const HermitHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermit Home',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      home: const _LaunchGate(),
      routes: {
        // Đã GỠ BỎ chữ 'const' ở phía trước các màn hình để tránh lỗi
        '/login': (_) => LoginScreen(),
        '/dashboard': (_) => DashboardScreen(),

        AuthRoutes.login: (_) => LoginScreen(),
        AuthRoutes.home: (_) => DashboardScreen(),
        AuthRoutes.dashboard: (_) => DashboardScreen(),
        AuthRoutes.apiTest: (_) => const UserApiTestScreen(),
      },
    );
  }
}

class _LaunchGate extends StatefulWidget {
  const _LaunchGate();

  @override
  State<_LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<_LaunchGate> {
  late final Future<bool> _isLoggedInFuture;

  @override
  void initState() {
    super.initState();
    _isLoggedInFuture = AuthService().isLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isLoggedInFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFF000B18),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF00D2FF)),
            ),
          );
        }

        final isLoggedIn = snapshot.data ?? false;
        // Đã GỠ BỎ chữ 'const' ở đây luôn
        return isLoggedIn ? DashboardScreen() : LoginScreen();
      },
    );
  }
}
