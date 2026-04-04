// lib/features/auth/presentation/login_screen.dart

import 'package:flutter/material.dart';

import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/app_theme.dart';
import 'widgets/auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ── Form ─────────────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _pwController = TextEditingController();

  // ── Focus nodes ──────────────────────────────────────────────────────────────
  // Used so tapping "Next" on the email keyboard moves focus to password.
  final _emailFocus = FocusNode();
  final _pwFocus = FocusNode();

  // ── State ────────────────────────────────────────────────────────────────────
  bool _isLoading = false;

  // ── Auth service ─────────────────────────────────────────────────────────────
  final _authService = AuthService();

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _emailController.dispose();
    _pwController.dispose();
    _emailFocus.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  // ── Submit ───────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    // Validate all fields first; bail out if any are invalid.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Dismiss keyboard before the network call.
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    final result = await _authService.login(
      email: _emailController.text.trim(),
      password: _pwController.text,
    );

    // Guard against the widget being disposed while awaiting.
    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result.isSuccess) {
      // Replace the whole nav stack so the user cannot press Back to login.
      Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (_) => false);
    } else {
      _showError(result.errorMessage ?? 'Login failed. Please try again.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      // Remove any existing SnackBar first to avoid stacking.
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Single-child scroll view lets the form scroll up when the keyboard appears,
      // preventing "bottom overflowed" errors on small screens.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 64),
              _buildHeader(),
              const SizedBox(height: 40),
              _buildForm(),
              const SizedBox(height: 24),
              _buildBottomNav(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Column(
      children: [
        // Logo mark
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppTheme.primary.withOpacity(0.3), width: 1.5),
          ),
          child: const Center(
            child: Text('🐚', style: TextStyle(fontSize: 36)),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Hermit-Home',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Smart Terrarium Controller',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.subtle,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Sign in to your account',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  // ── Form ─────────────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Email
            EmailField(
              controller: _emailController,
              focusNode: _emailFocus,
              nextFocusNode: _pwFocus,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 14),

            // Password — triggers submit on "Done"
            PasswordField(
              controller: _pwController,
              focusNode: _pwFocus,
              enabled: !_isLoading,
              onSubmitted: _submit,
            ),
            const SizedBox(height: 24),

            // Submit
            AuthSubmitButton(
              label: 'Sign In',
              isLoading: _isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom navigation ─────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account?",
          style: TextStyle(color: AppTheme.subtle, fontSize: 13),
        ),
        TextButton(
          onPressed: _isLoading
              ? null
              : () => Navigator.of(context).pushNamed('/register'),
          child: const Text('Create one'),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RegisterScreen — kept in the same file so they can be imported together
// from main.dart, matching the existing project pattern.
// ══════════════════════════════════════════════════════════════════════════════

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ── Form ─────────────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _pwController = TextEditingController();
  final _confirmController = TextEditingController();

  // ── Focus nodes ──────────────────────────────────────────────────────────────
  final _emailFocus = FocusNode();
  final _pwFocus = FocusNode();
  final _confirmFocus = FocusNode();

  // ── State ────────────────────────────────────────────────────────────────────
  bool _isLoading = false;

  final _authService = AuthService();

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _emailController.dispose();
    _pwController.dispose();
    _confirmController.dispose();
    _emailFocus.dispose();
    _pwFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  // ── Submit ───────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    final result = await _authService.register(
      email: _emailController.text.trim(),
      password: _pwController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      // Show a success SnackBar, then navigate back to login.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Account created! Please sign in.'),
            ],
          ),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 3),
        ),
      );

      // Pop back to login so the user can sign in with their new credentials.
      // A brief delay lets the SnackBar appear before the screen transitions.
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Navigator.of(context).pop();
    } else {
      _showError(result.errorMessage ?? 'Registration failed.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        title: const Text('Create Account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              _buildHeader(),
              const SizedBox(height: 32),
              _buildForm(),
              const SizedBox(height: 24),
              _buildBottomNav(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Column(
      children: [
        Text(
          'Join Hermit-Home',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Create your operator account',
          style: TextStyle(fontSize: 13, color: AppTheme.subtle),
        ),
      ],
    );
  }

  // ── Form ─────────────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Email
            EmailField(
              controller: _emailController,
              focusNode: _emailFocus,
              nextFocusNode: _pwFocus,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 14),

            // Password
            PasswordField(
              controller: _pwController,
              focusNode: _pwFocus,
              label: 'Password',
              enabled: !_isLoading,
              onSubmitted: () => _confirmFocus.requestFocus(),
            ),
            const SizedBox(height: 14),

            // Confirm password — uses the same PasswordField widget but with
            // an extra validator that compares against the first field.
            PasswordField(
              controller: _confirmController,
              focusNode: _confirmFocus,
              label: 'Confirm password',
              enabled: !_isLoading,
              onSubmitted: _submit,
              extraValidator: (value) {
                if (value != _pwController.text) {
                  return 'Passwords do not match.';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Submit
            AuthSubmitButton(
              label: 'Create Account',
              isLoading: _isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom navigation ─────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account?',
          style: TextStyle(color: AppTheme.subtle, fontSize: 13),
        ),
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Sign in'),
        ),
      ],
    );
  }
}
