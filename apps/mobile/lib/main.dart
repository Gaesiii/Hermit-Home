import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/constants/app_constants.dart';
import 'core/services/auth_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_routes.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/register_screen.dart';
import 'features/dashboard/dashboard_screen.dart';

class ResetDeepLinkData {
  const ResetDeepLinkData({
    this.status,
    this.token,
    this.userId,
    this.expiresAt,
  });

  final String? status;
  final String? token;
  final String? userId;
  final DateTime? expiresAt;

  bool get hasPayload => status != null || token != null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const HermitHomeApp());
}

class HermitHomeApp extends StatefulWidget {
  const HermitHomeApp({super.key});

  @override
  State<HermitHomeApp> createState() => _HermitHomeAppState();
}

class _HermitHomeAppState extends State<HermitHomeApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  ResetDeepLinkData? _initialResetData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _consumeInitialDeepLink();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPushRoute(String route) async {
    return _handleIncomingRoute(route, navigate: true);
  }

  @override
  Future<bool> didPushRouteInformation(
      RouteInformation routeInformation) async {
    final location = routeInformation.uri.toString();
    return _handleIncomingRoute(location, navigate: true);
  }

  Future<void> _consumeInitialDeepLink() async {
    final initialRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    _handleIncomingRoute(initialRoute, navigate: false);
  }

  bool _handleIncomingRoute(String? route, {required bool navigate}) {
    final resetData = _extractResetDeepLink(route);
    if (resetData == null) {
      return false;
    }

    if (navigate) {
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        AuthRoutes.login,
        (_) => false,
        arguments: resetData,
      );
      return true;
    }

    setState(() => _initialResetData = resetData);
    return true;
  }

  ResetDeepLinkData? _extractResetDeepLink(String? rawRoute) {
    if (rawRoute == null) {
      return null;
    }

    final normalizedRoute = rawRoute.trim();
    if (normalizedRoute.isEmpty || normalizedRoute == '/') {
      return null;
    }

    final uri = Uri.tryParse(normalizedRoute);
    if (uri == null) {
      return null;
    }

    final expectedScheme = AppConstants.resetLinkScheme.toLowerCase();
    final expectedHost = AppConstants.resetLinkHost.toLowerCase();
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final routeText = normalizedRoute.toLowerCase();

    final matchesCustomScheme = scheme == expectedScheme &&
        (host == expectedHost || (host.isEmpty && path.contains(expectedHost)));
    final matchesResetPath = host == expectedHost ||
        path.contains(expectedHost) ||
        routeText.contains(expectedHost);

    if (!(matchesCustomScheme || matchesResetPath)) {
      return null;
    }

    final token = _readNonEmptyQuery(uri, 'token');
    final userId = _readNonEmptyQuery(uri, 'userId');
    final rawStatus = _readNonEmptyQuery(uri, 'status');
    final status = _normalizeResetStatus(rawStatus, token: token);
    final expiresAtRaw = _readNonEmptyQuery(uri, 'expiresAt');
    final expiresAt =
        expiresAtRaw == null ? null : DateTime.tryParse(expiresAtRaw);

    final resetData = ResetDeepLinkData(
      status: status,
      token: token,
      userId: userId,
      expiresAt: expiresAt,
    );

    return resetData.hasPayload ? resetData : null;
  }

  String? _readNonEmptyQuery(Uri uri, String key) {
    final value = uri.queryParameters[key]?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  String? _normalizeResetStatus(String? rawStatus, {required String? token}) {
    final normalized = rawStatus?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return token == null ? null : 'valid';
    }

    if (normalized == 'valid' && token == null) {
      return 'missing_token';
    }

    return normalized;
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    if (settings.name == AuthRoutes.login) {
      final ResetDeepLinkData? resetData = switch (settings.arguments) {
        ResetDeepLinkData data => data,
        String token => ResetDeepLinkData(status: 'valid', token: token),
        _ => _initialResetData,
      };
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => LoginScreen(
          resetToken: resetData?.token,
          resetStatus: resetData?.status,
          resetUserId: resetData?.userId,
          resetExpiresAt: resetData?.expiresAt,
        ),
      );
    }

    if (settings.name == AuthRoutes.register) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const RegisterScreen(),
      );
    }

    if (settings.name == AuthRoutes.home ||
        settings.name == AuthRoutes.dashboard) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const DashboardScreen(),
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermit Home',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      navigatorKey: _navigatorKey,
      onGenerateRoute: _onGenerateRoute,
      home: _LaunchGate(initialResetData: _initialResetData),
    );
  }
}

class _LaunchGate extends StatefulWidget {
  const _LaunchGate({this.initialResetData});

  final ResetDeepLinkData? initialResetData;

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
    final initialResetData = widget.initialResetData;
    if (initialResetData != null && initialResetData.hasPayload) {
      return LoginScreen(
        resetToken: initialResetData.token,
        resetStatus: initialResetData.status,
        resetUserId: initialResetData.userId,
        resetExpiresAt: initialResetData.expiresAt,
      );
    }

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
