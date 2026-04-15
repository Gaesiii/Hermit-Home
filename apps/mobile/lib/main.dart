import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/user_api_test_screen.dart';
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
      title: 'Hermit-Home API Tester',
      debugShowCheckedModeBanner: false,
      initialRoute: '/api-test',
      routes: {
        '/api-test': (_) => const UserApiTestScreen(),
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/dashboard': (_) => const DashboardScreen(),
      },
    );
  }
}
