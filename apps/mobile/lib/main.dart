import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/services/auth_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_routes.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/register_screen.dart';
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
        AuthRoutes.login: (_) => const LoginScreen(),
        AuthRoutes.register: (_) => const RegisterScreen(),
        AuthRoutes.home: (_) => const DashboardScreen(),
        AuthRoutes.dashboard: (_) => const DashboardScreen(),
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
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final isLoggedIn = snapshot.data ?? false;
        return isLoggedIn ? const DashboardScreen() : const LoginScreen();
      },
    );
  }
}
