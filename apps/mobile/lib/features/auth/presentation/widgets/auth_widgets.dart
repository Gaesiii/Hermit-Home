// lib/features/auth/presentation/widgets/auth_widgets.dart
import 'package:flutter/material.dart';

class AuthScreenBackground extends StatelessWidget {
  const AuthScreenBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A3D62), Color(0xFF90CAF9)],
        ),
      ),
      child: child,
    );
  }
}

class HermitShellLogo extends StatelessWidget {
  const HermitShellLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('🐚', style: TextStyle(fontSize: 80));
  }
}

// ==================== GLASS TEXTFIELD (ĐÃ SỬA ĐẦY ĐỦ) ====================
class GlassTextField extends StatelessWidget {
  const GlassTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.nextFocusNode,
    required this.label,
    this.hint = '',
    this.obscureText = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final String label;
  final String hint;
  final bool obscureText;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      textInputAction:
          nextFocusNode != null ? TextInputAction.next : TextInputAction.done,
      onFieldSubmitted: (_) => onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white.withOpacity(0.85),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF42A5F5), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      ),
      style: const TextStyle(fontSize: 16.5, color: Colors.black87),
      validator: (value) {
        if (value == null || value.isEmpty) return '$label không được để trống';
        if (label.contains('Mật khẩu') && value.length < 8) {
          return 'Mật khẩu phải có ít nhất 8 ký tự';
        }
        return null;
      },
    );
  }
}

class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: isLoading
          ? const CircularProgressIndicator(color: Colors.white)
          : Text(label, style: const TextStyle(fontSize: 16)),
    );
  }
}
