// lib/features/auth/presentation/widgets/auth_widgets.dart
//
// Small, focused widgets shared by LoginScreen and RegisterScreen.
// Keeping them separate avoids code duplication and makes each widget
// independently testable.

import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';

// ── Email field ──────────────────────────────────────────────────────────────

class EmailField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool enabled;

  const EmailField({
    super.key,
    required this.controller,
    this.focusNode,
    this.nextFocusNode,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      // Move focus to the password field when the user presses "Next".
      onFieldSubmitted: (_) => nextFocusNode?.requestFocus(),
      decoration: const InputDecoration(
        labelText: 'Email address',
        hintText: 'you@example.com',
        prefixIcon: Icon(Icons.email_outlined),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Email is required.';
        }
        // Simple RFC-5322-ish check — same as the backend uses.
        final emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
        if (!emailRe.hasMatch(value.trim())) {
          return 'Please enter a valid email address.';
        }
        return null;
      },
    );
  }
}

// ── Password field ───────────────────────────────────────────────────────────

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final bool enabled;
  final String? Function(String?)? extraValidator;
  final VoidCallback? onSubmitted;

  const PasswordField({
    super.key,
    required this.controller,
    this.focusNode,
    this.label = 'Password',
    this.enabled = true,
    this.extraValidator,
    this.onSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      obscureText: _obscure,
      textInputAction: widget.onSubmitted != null
          ? TextInputAction.done
          : TextInputAction.next,
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: '••••••••',
        prefixIcon: const Icon(Icons.lock_outline),
        // Toggle button — clear affordance that it changes visibility.
        suffixIcon: IconButton(
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          tooltip: _obscure ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Password is required.';
        }
        if (value.length < 8) {
          return 'Password must be at least 8 characters.';
        }
        // Allow each screen to add its own extra rule (e.g. confirm check).
        return widget.extraValidator?.call(value);
      },
    );
  }
}

// ── Submit button ────────────────────────────────────────────────────────────
//
// Shows a spinner instead of the label while [isLoading] is true,
// and disables itself to prevent double-submission.

class AuthSubmitButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      // Disable during loading to prevent double submissions.
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                // Use onPrimary so it contrasts with the green button background.
                color: Colors.black,
              ),
            )
          : Text(label.toUpperCase()),
    );
  }
}

// ── Section divider ──────────────────────────────────────────────────────────

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppTheme.subtle, thickness: 0.5)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR',
            style: TextStyle(
              color: AppTheme.subtle,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppTheme.subtle, thickness: 0.5)),
      ],
    );
  }
}
