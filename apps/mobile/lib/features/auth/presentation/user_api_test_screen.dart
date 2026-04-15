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

  bool _isBusy = false;
  bool _hidePassword = true;
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
    super.dispose();
  }

  String get _normalizedBaseUrl =>
      _baseUrlController.text.trim().replaceFirst(RegExp(r'/+$'), '');

  Future<void> _reloadSession() async {
    final snapshot = await _service.readSession();
    if (!mounted) return;
    setState(() => _session = snapshot);
  }

  Future<void> _runRegister() async {
    if (!_validateForm(requirePassword: true)) return;
    await _runCall(() {
      return _service.register(
        baseUrl: _normalizedBaseUrl,
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    });
  }

  Future<void> _runLogin() async {
    if (!_validateForm(requirePassword: true)) return;
    await _runCall(() {
      return _service.login(
        baseUrl: _normalizedBaseUrl,
        email: _emailController.text.trim(),
        password: _passwordController.text,
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

  bool _validateForm({required bool requirePassword}) {
    final baseUrl = _normalizedBaseUrl;
    if (baseUrl.isEmpty || !baseUrl.startsWith('http')) {
      _showSnack('Base URL must start with http:// or https://');
      return false;
    }

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

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatResult(ApiProbeResult result) {
    final StringBuffer buffer = StringBuffer()
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
      ..writeln('Response Body:')
      ..writeln(_prettyJsonOrRaw(result.responseBody));

    return buffer.toString();
  }

  String _prettyJsonOrRaw(String text) {
    if (text.trim().isEmpty) return '(empty)';

    try {
      final decoded = jsonDecode(text);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      return text;
    }
  }

  String _tokenPreview(String? token) {
    if (token == null || token.isEmpty) {
      return '(none)';
    }
    if (token.length <= 20) {
      return token;
    }
    return '${token.substring(0, 10)}...${token.substring(token.length - 10)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User API Test'),
        actions: [
          IconButton(
            onPressed: _isBusy ? null : _reloadSession,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload saved session',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildConfigCard(),
              const SizedBox(height: 12),
              _buildAuthButtons(),
              const SizedBox(height: 12),
              _buildSessionCard(),
              const SizedBox(height: 12),
              _buildOutputCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Request Setup',
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
                  onPressed:
                      _isBusy ? null : () => setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                    _hidePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthButtons() {
    return Wrap(
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
          onPressed: _isBusy ? null : _reloadSession,
          icon: const Icon(Icons.key),
          label: const Text('Load Saved Token'),
        ),
        OutlinedButton.icon(
          onPressed: _isBusy ? null : _clearSession,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear Session'),
        ),
      ],
    );
  }

  Widget _buildSessionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Saved Session (Secure Storage)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Email: ${_session.email ?? '(none)'}'),
            const SizedBox(height: 4),
            Text('Token: ${_tokenPreview(_session.token)}'),
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
                color: Colors.black.withOpacity(0.04),
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
