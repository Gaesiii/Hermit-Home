import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/user_api_test_service.dart';

class UserApiTestScreen extends StatefulWidget {
  const UserApiTestScreen({super.key});

  @override
  State<UserApiTestScreen> createState() => _UserApiTestScreenState();
}

class _UserApiTestScreenState extends State<UserApiTestScreen> {
  final UserApiTestService _service = UserApiTestService();

  final TextEditingController _baseUrlController =
      TextEditingController(text: AppConstants.apiBaseUrl);
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _deviceIdController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _historyLimitController =
      TextEditingController(text: '20');

  final TextEditingController _devicePatchBodyController =
      TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert({
      'mode': 'AUTO',
      'user_override': false,
      'relays': {
        'heater': false,
        'mist': false,
        'fan': false,
        'light': false,
      },
    }),
  );

  final TextEditingController _controlBodyController = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert({
      'fan': true,
    }),
  );

  final TextEditingController _overrideBodyController = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert({
      'user_override': true,
      'devices': {
        'heater': false,
        'mist': false,
        'fan': false,
        'light': true,
      },
    }),
  );

  bool _isBusy = false;
  bool _hidePassword = true;
  bool _useBearerToken = true;
  bool _useApiKey = false;
  SessionSnapshot _session = const SessionSnapshot(token: null, email: null);
  String _lastOutput = 'No requests yet.';

  @override
  void initState() {
    super.initState();
    _reloadSession();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _deviceIdController.dispose();
    _apiKeyController.dispose();
    _historyLimitController.dispose();
    _devicePatchBodyController.dispose();
    _controlBodyController.dispose();
    _overrideBodyController.dispose();
    super.dispose();
  }

  String get _normalizedBaseUrl =>
      _baseUrlController.text.trim().replaceFirst(RegExp(r'/+$'), '');

  String? get _selectedToken => _useBearerToken ? _session.token : null;

  String? get _selectedApiKey =>
      _useApiKey ? _apiKeyController.text.trim() : null;

  Future<void> _reloadSession() async {
    final snapshot = await _service.readSession();
    if (!mounted) return;

    setState(() => _session = snapshot);
    _fillDeviceIdFromTokenIfEmpty();
  }

  void _fillDeviceIdFromTokenIfEmpty() {
    if (_deviceIdController.text.trim().isNotEmpty) {
      return;
    }

    final inferredUserId = _service.extractUserIdFromJwt(_session.token);
    if (inferredUserId != null && inferredUserId.isNotEmpty) {
      _deviceIdController.text = inferredUserId;
    }
  }

  void _fillDeviceIdFromToken() {
    final inferredUserId = _service.extractUserIdFromJwt(_session.token);
    if (inferredUserId == null || inferredUserId.isEmpty) {
      _showSnack('Cannot infer userId from current token.');
      return;
    }

    setState(() => _deviceIdController.text = inferredUserId);
    _showSnack('Device ID filled from login token.');
  }

  Future<void> _runRegister() async {
    if (!_validateBaseAndCredentials(requirePassword: true)) return;

    await _runCall(() {
      return _service.register(
        baseUrl: _normalizedBaseUrl,
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    });
  }

  Future<void> _runLogin() async {
    if (!_validateBaseAndCredentials(requirePassword: true)) return;

    await _runCall(() {
      return _service.login(
        baseUrl: _normalizedBaseUrl,
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    });

    _fillDeviceIdFromTokenIfEmpty();
  }

  Future<void> _runGetDevices() async {
    if (!_validateBaseUrl()) return;

    await _runCall(() {
      return _service.getDevices(baseUrl: _normalizedBaseUrl);
    });
  }

  Future<void> _runGetSchedules() async {
    if (!_validateBaseUrl()) return;

    await _runCall(() {
      return _service.getSchedules(
        baseUrl: _normalizedBaseUrl,
        bearerToken: _selectedToken,
        apiKey: _selectedApiKey,
      );
    });
  }

  Future<void> _runGetDeviceById() async {
    final deviceId = _requireDeviceId();
    if (deviceId == null) return;

    await _runCall(() {
      return _service.getDeviceById(
        baseUrl: _normalizedBaseUrl,
        deviceId: deviceId,
        bearerToken: _selectedToken,
        apiKey: _selectedApiKey,
      );
    });
  }

  Future<void> _runPatchDeviceById() async {
    final deviceId = _requireDeviceId();
    if (deviceId == null) return;

    final patch = _parseJsonMap(_devicePatchBodyController.text, 'PATCH body');
    if (patch == null) return;

    await _runCall(() {
      return _service.patchDeviceById(
        baseUrl: _normalizedBaseUrl,
        deviceId: deviceId,
        patch: patch,
        bearerToken: _selectedToken,
        apiKey: _selectedApiKey,
      );
    });
  }

  Future<void> _runGetStatus() async {
    final deviceId = _requireDeviceId();
    if (deviceId == null) return;

    await _runCall(() {
      return _service.getDeviceStatus(
        baseUrl: _normalizedBaseUrl,
        deviceId: deviceId,
        bearerToken: _selectedToken,
        apiKey: _selectedApiKey,
      );
    });
  }

  Future<void> _runGetControlHistory() async {
    final deviceId = _requireDeviceId();
    if (deviceId == null) return;

    int? limit;
    final rawLimit = _historyLimitController.text.trim();
    if (rawLimit.isNotEmpty) {
      final parsed = int.tryParse(rawLimit);
      if (parsed == null || parsed <= 0) {
        _showSnack('History limit must be a positive integer.');
        return;
      }
      limit = parsed;
    }

    await _runCall(() {
      return _service.getControlHistory(
        baseUrl: _normalizedBaseUrl,
        deviceId: deviceId,
        limit: limit,
        bearerToken: _selectedToken,
        apiKey: _selectedApiKey,
      );
    });
  }

  Future<void> _runPostControl() async {
    final deviceId = _requireDeviceId();
    if (deviceId == null) return;

    final payload = _parseJsonMap(_controlBodyController.text, 'Control body');
    if (payload == null) return;

    await _runCall(() {
      return _service.postControlUpdate(
        baseUrl: _normalizedBaseUrl,
        deviceId: deviceId,
        payload: payload,
        bearerToken: _selectedToken,
        apiKey: _selectedApiKey,
      );
    });
  }

  Future<void> _runPostOverride() async {
    final deviceId = _requireDeviceId();
    if (deviceId == null) return;

    final payload =
        _parseJsonMap(_overrideBodyController.text, 'Override body');
    if (payload == null) return;

    await _runCall(() {
      return _service.sendOverride(
        baseUrl: _normalizedBaseUrl,
        deviceId: deviceId,
        payload: payload,
        bearerToken: _selectedToken,
        apiKey: _selectedApiKey,
      );
    });
  }

  Future<void> _runOptionsLogin() async {
    if (!_validateBaseUrl()) return;

    await _runCall(() {
      return _service.options(
        baseUrl: _normalizedBaseUrl,
        endpoint: AppConstants.loginEndpoint,
        bearerToken: _selectedToken,
        apiKey: _selectedApiKey,
      );
    });
  }

  Future<void> _runOptionsStatus() async {
    final deviceId = _requireDeviceId();
    if (deviceId == null) return;

    await _runCall(() {
      return _service.options(
        baseUrl: _normalizedBaseUrl,
        endpoint: AppConstants.deviceStatusEndpoint(deviceId),
        bearerToken: _selectedToken,
        apiKey: _selectedApiKey,
      );
    });
  }

  Future<void> _clearSession() async {
    setState(() => _isBusy = true);
    await _service.clearSession();
    await _reloadSession();

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _lastOutput = '[LOCAL] Cleared saved token/email from secure storage.';
    });
  }

  Future<void> _runCall(Future<ApiProbeResult> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() => _isBusy = true);

    final result = await action();
    await _reloadSession();

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _lastOutput = _formatResult(result);
    });
  }

  bool _validateBaseAndCredentials({required bool requirePassword}) {
    if (!_validateBaseUrl()) return false;

    if (_emailController.text.trim().isEmpty) {
      _showSnack('Email is required.');
      return false;
    }

    if (requirePassword && _passwordController.text.isEmpty) {
      _showSnack('Password is required.');
      return false;
    }

    return true;
  }

  bool _validateBaseUrl() {
    final baseUrl = _normalizedBaseUrl;
    if (baseUrl.isEmpty || !baseUrl.startsWith('http')) {
      _showSnack('Base URL must start with http:// or https://');
      return false;
    }

    return true;
  }

  String? _requireDeviceId() {
    if (!_validateBaseUrl()) return null;

    final deviceId = _deviceIdController.text.trim();
    if (deviceId.isEmpty) {
      _showSnack('Device ID is required for this endpoint.');
      return null;
    }

    return deviceId;
  }

  Map<String, dynamic>? _parseJsonMap(String text, String fieldLabel) {
    if (text.trim().isEmpty) {
      _showSnack('$fieldLabel cannot be empty.');
      return null;
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      _showSnack('$fieldLabel must be a JSON object.');
      return null;
    } catch (error) {
      _showSnack('Invalid JSON in $fieldLabel: $error');
      return null;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatResult(ApiProbeResult result) {
    final buffer = StringBuffer()
      ..writeln('[${result.timestamp.toIso8601String()}]')
      ..writeln('${result.method} ${result.url}')
      ..writeln('Status: ${result.statusCode ?? 'NO_RESPONSE'}');

    if (result.errorMessage != null) {
      buffer.writeln('Error: ${result.errorMessage}');
    }

    buffer
      ..writeln('')
      ..writeln('Request Body:')
      ..writeln(_prettyJsonOrRaw(result.requestBody))
      ..writeln('')
      ..writeln('Response Headers:')
      ..writeln(_prettyJsonOrRaw(jsonEncode(result.responseHeaders)))
      ..writeln('')
      ..writeln('Response Body:')
      ..writeln(_prettyJsonOrRaw(result.responseBody));

    return buffer.toString();
  }

  String _prettyJsonOrRaw(String text) {
    if (text.trim().isEmpty) return '(empty)';

    try {
      final decoded = jsonDecode(text);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return text;
    }
  }

  String _tokenPreview(String? token) {
    if (token == null || token.isEmpty) return '(none)';
    if (token.length <= 24) return token;
    return '${token.substring(0, 12)}...${token.substring(token.length - 12)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User + Device API Test'),
        actions: [
          IconButton(
            onPressed: _isBusy ? null : _reloadSession,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload session',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAuthConfigCard(),
              const SizedBox(height: 12),
              _buildSessionCard(),
              const SizedBox(height: 12),
              _buildRequestConfigCard(),
              const SizedBox(height: 12),
              _buildPayloadCard(),
              const SizedBox(height: 12),
              _buildQuickActionCard(),
              const SizedBox(height: 12),
              _buildOutputCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Auth Setup',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _baseUrlController,
              enabled: !_isBusy,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://hermit-home.vercel.app',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailController,
              enabled: !_isBusy,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@example.com',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              enabled: !_isBusy,
              obscureText: _hidePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  onPressed: _isBusy
                      ? null
                      : () => setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                      _hidePassword ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: _isBusy ? null : _runRegister,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Register'),
                ),
                ElevatedButton.icon(
                  onPressed: _isBusy ? null : _runLogin,
                  icon: const Icon(Icons.login),
                  label: const Text('Login'),
                ),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _clearSession,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear Session'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard() {
    final inferredUserId = _service.extractUserIdFromJwt(_session.token);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Saved Session (Local)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Email: ${_session.email ?? '(none)'}'),
            const SizedBox(height: 4),
            Text('Token: ${_tokenPreview(_session.token)}'),
            const SizedBox(height: 4),
            Text('Decoded userId: ${inferredUserId ?? '(none)'}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _reloadSession,
                  icon: const Icon(Icons.key),
                  label: const Text('Reload Token'),
                ),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _fillDeviceIdFromToken,
                  icon: const Icon(Icons.link),
                  label: const Text('Use userId as deviceId'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Device Request Setup',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _deviceIdController,
              enabled: !_isBusy,
              decoration: const InputDecoration(
                labelText: 'deviceId',
                hintText: '24-char Mongo ObjectId',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _historyLimitController,
              enabled: !_isBusy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Control history limit',
                hintText: '20',
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _useBearerToken,
              onChanged: _isBusy
                  ? null
                  : (value) => setState(() => _useBearerToken = value),
              title: const Text('Use Bearer token'),
              subtitle: const Text('Authorization: Bearer <saved token>'),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _useApiKey,
              onChanged: _isBusy
                  ? null
                  : (value) => setState(() => _useApiKey = value),
              title: const Text('Use X-API-Key'),
              subtitle: const Text('Service-to-service auth path'),
            ),
            if (_useApiKey)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _apiKeyController,
                  enabled: !_isBusy,
                  decoration: const InputDecoration(
                    labelText: 'SERVICE_API_KEY',
                    hintText: 'Paste API key here',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayloadCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'JSON Payload Templates',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _buildJsonEditor(
              label: 'PATCH /api/devices/{deviceId}',
              controller: _devicePatchBodyController,
            ),
            const SizedBox(height: 10),
            _buildJsonEditor(
              label: 'POST /api/devices/{deviceId}/control',
              controller: _controlBodyController,
            ),
            const SizedBox(height: 10),
            _buildJsonEditor(
              label: 'POST /api/devices/{deviceId}/override',
              controller: _overrideBodyController,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJsonEditor({
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: !_isBusy,
          minLines: 4,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Quick API Actions',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton(
                  onPressed: _isBusy ? null : _runGetDevices,
                  child: const Text('GET /api/devices'),
                ),
                ElevatedButton(
                  onPressed: _isBusy ? null : _runGetSchedules,
                  child: const Text('GET /api/devices/schedules'),
                ),
                ElevatedButton(
                  onPressed: _isBusy ? null : _runGetDeviceById,
                  child: const Text('GET /api/devices/{id}'),
                ),
                ElevatedButton(
                  onPressed: _isBusy ? null : _runPatchDeviceById,
                  child: const Text('PATCH /api/devices/{id}'),
                ),
                ElevatedButton(
                  onPressed: _isBusy ? null : _runGetStatus,
                  child: const Text('GET /status'),
                ),
                ElevatedButton(
                  onPressed: _isBusy ? null : _runGetControlHistory,
                  child: const Text('GET /control'),
                ),
                ElevatedButton(
                  onPressed: _isBusy ? null : _runPostControl,
                  child: const Text('POST /control'),
                ),
                ElevatedButton(
                  onPressed: _isBusy ? null : _runPostOverride,
                  child: const Text('POST /override'),
                ),
                OutlinedButton(
                  onPressed: _isBusy ? null : _runOptionsLogin,
                  child: const Text('OPTIONS /api/users/login'),
                ),
                OutlinedButton(
                  onPressed: _isBusy ? null : _runOptionsStatus,
                  child: const Text('OPTIONS /status'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Last API Result',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(minHeight: 220),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _lastOutput,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
