import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_routes.dart';
import 'data/device_control_repository.dart';
import 'data/telemetry_repository.dart';
import 'domain/device_control_state.dart';
import 'domain/telemetry_model.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService _authService = AuthService();
  final TelemetryRepository _telemetryRepository = TelemetryRepository();
  final DeviceControlRepository _deviceControlRepository =
      DeviceControlRepository();

  bool _isLoading = true;

  String? _email;
  String? _token;
  String? _userId;
  DateTime? _accountCreatedAt;
  DateTime? _lastLoginAt;
  _JwtSessionInfo _jwtInfo = const _JwtSessionInfo();

  List<TelemetryModel> _telemetry = const [];
  String? _telemetryError;

  DeviceControlState _deviceState = DeviceControlState.initial;
  DateTime? _deviceStateUpdatedAt;
  int _deviceStateHistoryCount = 0;
  String? _deviceStateError;
  final Set<String> _pendingControlKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    final values = await Future.wait<Object?>([
      _authService.getEmail(),
      _authService.getToken(),
      _authService.getUserId(),
      _authService.getAccountCreatedAt(),
      _authService.getLastLoginAt(),
    ]);

    if (!mounted) return;

    final email = values[0] as String?;
    final token = values[1] as String?;
    final storedUserId = values[2] as String?;
    final accountCreatedAt = values[3] as DateTime?;
    final lastLoginAt = values[4] as DateTime?;

    final sessionInfo = _JwtSessionInfo.fromToken(token);
    final resolvedUserId = storedUserId ?? sessionInfo.userId;

    List<TelemetryModel> telemetry = const [];
    String? telemetryError;

    DeviceControlSnapshot controlSnapshot = const DeviceControlSnapshot(
      state: DeviceControlState.initial,
      historyCount: 0,
    );
    String? controlError;

    if (resolvedUserId == null || resolvedUserId.isEmpty) {
      telemetryError = 'Cannot find userId in current session.';
      controlError = 'Cannot find userId in current session.';
    } else if (token == null || token.isEmpty) {
      telemetryError = 'Cannot find valid access token.';
      controlError = 'Cannot find valid access token.';
    } else {
      try {
        telemetry = await _telemetryRepository.fetchByUserId(
          userId: resolvedUserId,
          token: token,
          limit: 40,
        );
      } catch (error) {
        telemetryError = error.toString().replaceFirst('Exception: ', '');
      }

      try {
        controlSnapshot = await _deviceControlRepository.fetchCurrentState(
          userId: resolvedUserId,
          token: token,
          limit: 100,
        );
      } catch (error) {
        controlError = error.toString().replaceFirst('Exception: ', '');
      }
    }

    if (!mounted) return;

    setState(() {
      _email = email;
      _token = token;
      _userId = resolvedUserId;
      _accountCreatedAt = accountCreatedAt;
      _lastLoginAt = lastLoginAt;
      _jwtInfo = sessionInfo;

      _telemetry = telemetry;
      _telemetryError = telemetryError;

      _deviceState = controlSnapshot.state;
      _deviceStateUpdatedAt = controlSnapshot.lastUpdatedAt;
      _deviceStateHistoryCount = controlSnapshot.historyCount;
      _deviceStateError = controlError;
      _pendingControlKeys.clear();

      _isLoading = false;
    });
  }

  Future<void> _toggleDevice(String deviceKey, bool enabled) async {
    final userId = _userId;
    final token = _token;

    if (userId == null || userId.isEmpty || token == null || token.isEmpty) {
      _showSnack('Session is missing userId or token. Please sign in again.');
      return;
    }

    if (_pendingControlKeys.contains(deviceKey)) {
      return;
    }

    final previousValue = _deviceState.valueForKey(deviceKey);

    setState(() {
      _pendingControlKeys.add(deviceKey);
      _deviceState = _deviceState.withKey(deviceKey, enabled);
    });

    try {
      final result = await _deviceControlRepository.setDeviceState(
        userId: userId,
        token: token,
        deviceKey: deviceKey,
        enabled: enabled,
      );

      if (!mounted) return;

      setState(() {
        _deviceState = _deviceState.withKey(deviceKey, result.appliedValue);
        _deviceStateUpdatedAt = DateTime.now();
        _pendingControlKeys.remove(deviceKey);
        _deviceStateError = null;
      });

      if (result.mistLockedOff) {
        _showSnack('Mist safety lock is active. Mist remains OFF.');
      }
    } catch (error) {
      if (!mounted) return;

      final errorMessage = error.toString().replaceFirst('Exception: ', '');

      setState(() {
        _deviceState = _deviceState.withKey(deviceKey, previousValue);
        _pendingControlKeys.remove(deviceKey);
        _deviceStateError = errorMessage;
      });

      _showSnack(errorMessage);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.error,
        ),
      );
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;

    Navigator.of(context)
        .pushNamedAndRemoveUntil(AuthRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadSession,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh data',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSession,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildWelcomeCard(),
                  const SizedBox(height: 14),
                  _buildProfileCard(),
                  const SizedBox(height: 14),
                  _buildDeviceControlsCard(),
                  const SizedBox(height: 14),
                  _buildTelemetryCard(),
                  const SizedBox(height: 14),
                  _buildSessionCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildWelcomeCard() {
    final sessionLabel = _jwtInfo.expiresAt == null
        ? 'Unknown'
        : _jwtInfo.isExpired
            ? 'Expired'
            : 'Active';

    final badgeColor = _jwtInfo.expiresAt == null
        ? Colors.grey
        : _jwtInfo.isExpired
            ? AppTheme.error
            : AppTheme.primary;

    return Container(
      decoration: AppTheme.cardDecoration(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome back',
                  style: TextStyle(fontSize: 13, color: AppTheme.subtle),
                ),
                const SizedBox(height: 4),
                Text(
                  _email ?? 'No email found',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: badgeColor.withValues(alpha: 0.45)),
            ),
            child: Text(
              sessionLabel,
              style: TextStyle(
                color: badgeColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      decoration: AppTheme.cardDecoration(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'User Info',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.mail_outline_rounded,
            label: 'Email',
            value: _email ?? 'Not available',
          ),
          _InfoRow(
            icon: Icons.badge_outlined,
            label: 'User ID',
            value: _userId ?? 'Not available',
          ),
          _InfoRow(
            icon: Icons.calendar_month_outlined,
            label: 'Account created',
            value: _formatDateTime(_accountCreatedAt),
          ),
          _InfoRow(
            icon: Icons.login_rounded,
            label: 'Last sign in',
            value: _formatDateTime(_lastLoginAt),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceControlsCard() {
    return Container(
      decoration: AppTheme.cardDecoration(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Device Controls',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF2A3530)),
                ),
                child: Text(
                  '$_deviceStateHistoryCount events',
                  style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Last sync: ${_formatDateTime(_deviceStateUpdatedAt)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
          ),
          if (_deviceStateError != null) ...[
            const SizedBox(height: 8),
            Text(
              _deviceStateError!,
              style: const TextStyle(color: AppTheme.error, height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          _DeviceControlTile(
            label: 'Den',
            subtitle: 'Light relay',
            icon: Icons.lightbulb_outline_rounded,
            value: _deviceState.light,
            isBusy: _pendingControlKeys.contains('light'),
            onChanged: (value) => _toggleDevice('light', value),
          ),
          const SizedBox(height: 10),
          _DeviceControlTile(
            label: 'Quat',
            subtitle: 'Fan relay',
            icon: Icons.air_rounded,
            value: _deviceState.fan,
            isBusy: _pendingControlKeys.contains('fan'),
            onChanged: (value) => _toggleDevice('fan', value),
          ),
          const SizedBox(height: 10),
          _DeviceControlTile(
            label: 'Phun suong',
            subtitle: 'Mist relay',
            icon: Icons.water_drop_outlined,
            value: _deviceState.mist,
            isBusy: _pendingControlKeys.contains('mist'),
            onChanged: (value) => _toggleDevice('mist', value),
          ),
          const SizedBox(height: 10),
          _DeviceControlTile(
            label: 'Suoi',
            subtitle: 'Heater relay',
            icon: Icons.local_fire_department_outlined,
            value: _deviceState.heater,
            isBusy: _pendingControlKeys.contains('heater'),
            onChanged: (value) => _toggleDevice('heater', value),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryCard() {
    return Container(
      decoration: AppTheme.cardDecoration(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Telemetry',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF2A3530)),
                ),
                child: Text(
                  '${_telemetry.length} records',
                  style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_telemetryError != null) ...[
            Text(
              _telemetryError!,
              style: const TextStyle(color: AppTheme.error, height: 1.4),
            ),
          ] else if (_telemetry.isEmpty) ...[
            const Text(
              'No telemetry records for this userId yet.',
              style: TextStyle(color: AppTheme.subtle),
            ),
          ] else ...[
            for (var i = 0; i < _telemetry.length; i++)
              _TelemetryTile(
                telemetry: _telemetry[i],
                isLast: i == _telemetry.length - 1,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionCard() {
    return Container(
      decoration: AppTheme.cardDecoration(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Session Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.vpn_key_outlined,
            label: 'Token preview',
            value: _tokenPreview(_token),
          ),
          _InfoRow(
            icon: Icons.schedule_rounded,
            label: 'Issued at',
            value: _formatDateTime(_jwtInfo.issuedAt),
          ),
          _InfoRow(
            icon: Icons.event_busy_outlined,
            label: 'Expires at',
            value: _formatDateTime(_jwtInfo.expiresAt),
          ),
          const _InfoRow(
            icon: Icons.link_rounded,
            label: 'API endpoint',
            value: AppConstants.apiBaseUrl,
            isLast: true,
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Not available';

    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }

  String _tokenPreview(String? token) {
    if (token == null || token.isEmpty) {
      return 'Not available';
    }

    if (token.length <= 24) {
      return token;
    }

    final head = token.substring(0, 12);
    final tail = token.substring(token.length - 10);
    return '$head...$tail';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A3530)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppTheme.subtle),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style:
                        const TextStyle(fontSize: 12, color: AppTheme.subtle),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 14, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceControlTile extends StatelessWidget {
  const _DeviceControlTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.isBusy,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool value;
  final bool isBusy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3530)),
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? AppTheme.primary : AppTheme.subtle),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
                ),
              ],
            ),
          ),
          if (isBusy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppTheme.primary,
            ),
        ],
      ),
    );
  }
}

class _TelemetryTile extends StatelessWidget {
  const _TelemetryTile({
    required this.telemetry,
    required this.isLast,
  });

  final TelemetryModel telemetry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3530)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatTimestamp(telemetry.timestamp),
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.subtle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ValueChip(
                label: 'Nhiet do',
                value: _formatNumber(telemetry.temperature, suffix: ' degC'),
              ),
              _ValueChip(
                label: 'Do am',
                value: _formatNumber(telemetry.humidity, suffix: '%'),
              ),
              _ValueChip(
                label: 'Lux',
                value: _formatNumber(telemetry.lux, precision: 0),
              ),
              _ValueChip(
                label: 'Sensor',
                value: telemetry.sensorFault ? 'Fault' : 'OK',
              ),
              _ValueChip(
                label: 'Override',
                value: telemetry.userOverride ? 'ON' : 'OFF',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Relay: H:${_state(telemetry.relays.heater)} '
            'M:${_state(telemetry.relays.mist)} '
            'F:${_state(telemetry.relays.fan)} '
            'L:${_state(telemetry.relays.light)}',
            style: const TextStyle(fontSize: 12.5, color: AppTheme.subtle),
          ),
        ],
      ),
    );
  }

  static String _formatTimestamp(DateTime dateTime) {
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute:$second';
  }

  static String _formatNumber(
    double? value, {
    int precision = 1,
    String suffix = '',
  }) {
    if (value == null) {
      return '--';
    }
    return '${value.toStringAsFixed(precision)}$suffix';
  }

  static String _state(bool enabled) => enabled ? 'ON' : 'OFF';
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2A3530)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _JwtSessionInfo {
  const _JwtSessionInfo({
    this.userId,
    this.issuedAt,
    this.expiresAt,
  });

  final String? userId;
  final DateTime? issuedAt;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!.toUtc());

  static _JwtSessionInfo fromToken(String? token) {
    if (token == null || token.isEmpty) {
      return const _JwtSessionInfo();
    }

    final segments = token.split('.');
    if (segments.length < 2) {
      return const _JwtSessionInfo();
    }

    try {
      final payloadSegment = base64Url.normalize(segments[1]);
      final payloadRaw = utf8.decode(base64Url.decode(payloadSegment));
      final payload = jsonDecode(payloadRaw);

      if (payload is! Map<String, dynamic>) {
        return const _JwtSessionInfo();
      }

      return _JwtSessionInfo(
        userId: _readString(payload['userId']),
        issuedAt: _readEpochSeconds(payload['iat']),
        expiresAt: _readEpochSeconds(payload['exp']),
      );
    } catch (_) {
      return const _JwtSessionInfo();
    }
  }

  static String? _readString(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static DateTime? _readEpochSeconds(Object? value) {
    int? seconds;

    if (value is int) {
      seconds = value;
    } else if (value is num) {
      seconds = value.toInt();
    } else if (value is String) {
      seconds = int.tryParse(value);
    }

    if (seconds == null) return null;

    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
        .toLocal();
  }
}
