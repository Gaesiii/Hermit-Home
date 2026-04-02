// lib/main.dart
//
// App entry point.
// Checks secure storage for a saved token before deciding the first screen:
//   • Token found  → Dashboard (skip login)
//   • Token absent → Login screen

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/services/auth_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/dashboard/dashboard_screen.dart';

void main() async {
  // Required before any async work before runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait — common for phone-first IoT dashboards.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Resolve the initial screen once before the widget tree is built.
  // Avoids a flash of the login screen for already-authenticated users.
  final isLoggedIn = await AuthService().isLoggedIn();

  runApp(HermitHomeApp(isLoggedIn: isLoggedIn));
}

class HermitHomeApp extends StatelessWidget {
  final bool isLoggedIn;
  const HermitHomeApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermit-Home',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,

      // Named routes — screens push/pop by name, keeping navigation
      // logic out of the widgets themselves.
      initialRoute: isLoggedIn ? '/dashboard' : '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/dashboard': (_) => const DashboardScreen(),
      },
    );
  }
}
