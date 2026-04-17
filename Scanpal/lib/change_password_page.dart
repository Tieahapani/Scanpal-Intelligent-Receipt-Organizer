import 'package:flutter/material.dart';
import 'api.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _hasMinLength => _newCtrl.text.length >= 8;
  bool get _hasUppercase => _newCtrl.text.contains(RegExp(r'[A-Z]'));
  bool get _hasLowercase => _newCtrl.text.contains(RegExp(r'[a-z]'));
  bool get _hasDigit => _newCtrl.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecial => _newCtrl.text.contains(RegExp(r'[!@#$%^&*()_+\-=\[\]{}|;:,.<>?/]'));
  bool get _passwordsMatch => _newCtrl.text == _confirmCtrl.text && _confirmCtrl.text.isNotEmpty;
  bool get _isValid =>
      _currentCtrl.text.isNotEmpty &&
      _hasMinLength &&
      _hasUppercase &&
      _hasLowercase &&
      _hasDigit &&
      _hasSpecial &&
      _passwordsMatch;

  Future<void> _submit() async {
    if (!_isValid) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await APIService().changePassword(_currentCtrl.text, _newCtrl.text);
      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF46166B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Password changed successfully',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Widget _requirementRow(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: met ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: met ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
              letterSpacing: 0.5,
            ),
          ),
        ),
        TextField(
          controller: controller,
          obscureText: obscure,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF9CA3AF), size: 20),
            suffixIcon: GestureDetector(
              onTap: onToggle,
              child: Icon(
                obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: const Color(0xFF9CA3AF),
                size: 20,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF46166B), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Back button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF3F4F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      size: 20,
                      color: Color(0xFF46166B),
                    ),
                  ),
                ),
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 16),

                    // Key icon
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF46166B).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.vpn_key_outlined,
                        size: 32,
                        color: Color(0xFF46166B),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    const Text(
                      'Change Password',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF46166B),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Subtitle
                    const Text(
                      'Enter your current password and choose\na new password',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Current password
                    _passwordField(
                      controller: _currentCtrl,
                      hint: 'Enter current password',
                      label: 'CURRENT PASSWORD',
                      obscure: _obscureCurrent,
                      onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                    const SizedBox(height: 16),

                    // New password
                    _passwordField(
                      controller: _newCtrl,
                      hint: 'Enter new password',
                      label: 'NEW PASSWORD',
                      obscure: _obscureNew,
                      onToggle: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                    const SizedBox(height: 16),

                    // Confirm password
                    _passwordField(
                      controller: _confirmCtrl,
                      hint: 'Confirm new password',
                      label: 'CONFIRM PASSWORD',
                      obscure: _obscureConfirm,
                      onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    const SizedBox(height: 20),

                    // Requirements checklist
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _requirementRow('At least 8 characters', _hasMinLength),
                          _requirementRow('1 uppercase letter', _hasUppercase),
                          _requirementRow('1 lowercase letter', _hasLowercase),
                          _requirementRow('1 number', _hasDigit),
                          _requirementRow('1 special character (!@#\$%...)', _hasSpecial),
                          _requirementRow('Passwords match', _passwordsMatch),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Error
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Change Password button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading || !_isValid ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isValid ? const Color(0xFF46166B) : const Color(0xFFD1D5DB),
                          foregroundColor: Colors.white,
                          elevation: _isValid ? 2 : 0,
                          shadowColor: _isValid
                              ? const Color(0xFF46166B).withValues(alpha: 0.3)
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          disabledBackgroundColor: const Color(0xFFD1D5DB),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Text(
                                'Change Password',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                children: [
                  Opacity(
                    opacity: 0.3,
                    child: Image.asset(
                      'assets/asgo_logo.jpeg',
                      width: 64,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Associated Students \u00B7 SF State',
                    style: TextStyle(fontSize: 10, color: Color(0xFFD1D5DB)),
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
