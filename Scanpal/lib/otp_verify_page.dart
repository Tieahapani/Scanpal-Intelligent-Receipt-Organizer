import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'traveler_home_page.dart';
import 'admin_home_page.dart';

class OtpVerifyPage extends StatefulWidget {
  final String email;
  final String purpose; // "login" or "register"
  final bool rememberMe;

  const OtpVerifyPage({
    super.key,
    required this.email,
    required this.purpose,
    required this.rememberMe,
  });

  @override
  State<OtpVerifyPage> createState() => _OtpVerifyPageState();
}

class _OtpVerifyPageState extends State<OtpVerifyPage> {
  final List<TextEditingController> _digitControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  String? _error;
  bool _isResending = false;
  int _resendCooldown = 30;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendCooldown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendCooldown = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) {
          timer.cancel();
        }
      });
    });
  }

  String get _code => _digitControllers.map((c) => c.text).join();

  bool get _isCodeComplete => _code.length == 6;

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // Handle paste: distribute digits across fields
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0; i < digits.length && (index + i) < 6; i++) {
        _digitControllers[index + i].text = digits[i];
      }
      final lastIndex = (index + digits.length - 1).clamp(0, 5);
      _focusNodes[lastIndex].requestFocus();
      setState(() {});
      if (_isCodeComplete) {
        Future.delayed(const Duration(milliseconds: 400), _verify);
      }
      return;
    }

    setState(() {});

    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }

    if (_isCodeComplete) {
      Future.delayed(const Duration(milliseconds: 400), _verify);
    }
  }

  void _onKeyDown(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _digitControllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _verify() async {
    final code = _code;
    if (code.length != 6) {
      setState(() => _error = 'Please enter the 6-digit code');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = APIService();
      final result = await api.verifyOtp(
        widget.email,
        code,
        rememberMe: widget.rememberMe,
      );

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => result.user.isAdmin
              ? AdminHomePage(user: result.user)
              : TravelerHomePage(user: result.user),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _resendCode() async {
    if (_resendCooldown > 0) return;

    setState(() {
      _isResending = true;
      _error = null;
    });

    try {
      final api = APIService();
      await api.login(widget.email);
      if (!mounted) return;
      setState(() => _isResending = false);
      // Clear code fields
      for (final c in _digitControllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
      _startResendCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New code sent!'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF46166B),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _error = 'Failed to resend code. Please try again.';
      });
    }
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
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
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

                    // Mail icon circle
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF46166B).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mail_outline_rounded,
                        size: 32,
                        color: Color(0xFF46166B),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    const Text(
                      'Verify Your Email',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF46166B),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Subtitle
                    const Text(
                      "We've sent a 6-digit verification code to",
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.email,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF46166B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Code input boxes
                    Row(
                      children: List.generate(6, (index) {
                        final hasValue = _digitControllers[index].text.isNotEmpty;
                        return Expanded(
                          child: Container(
                            height: 56,
                            margin: EdgeInsets.only(right: index < 5 ? 8 : 0),
                            child: KeyboardListener(
                              focusNode: FocusNode(),
                              onKeyEvent: (event) => _onKeyDown(index, event),
                              child: TextField(
                                controller: _digitControllers[index],
                                focusNode: _focusNodes[index],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                maxLength: 6,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: hasValue ? const Color(0xFF46166B) : const Color(0xFF111827),
                                ),
                                decoration: InputDecoration(
                                  counterText: '',
                                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                  filled: true,
                                  fillColor: hasValue ? Colors.white : const Color(0xFFF9FAFB),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: hasValue ? const Color(0xFF46166B) : const Color(0xFFE5E7EB),
                                      width: 2,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: hasValue ? const Color(0xFF46166B) : const Color(0xFFE5E7EB),
                                      width: 2,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: hasValue ? const Color(0xFF46166B) : const Color(0xFFE8A824),
                                      width: 2,
                                    ),
                                  ),
                                ),
                                onChanged: (value) => _onDigitChanged(index, value),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),

                    // Error message
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
                            Icon(Icons.error_outline,
                                color: Colors.red.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Verify button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _verify,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isCodeComplete
                              ? const Color(0xFF46166B)
                              : const Color(0xFFD1D5DB),
                          foregroundColor: Colors.white,
                          elevation: _isCodeComplete ? 2 : 0,
                          shadowColor: _isCodeComplete
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Verify & Continue',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Resend code
                    _isResending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              color: Color(0xFF9CA3AF),
                              strokeWidth: 2,
                            ),
                          )
                        : GestureDetector(
                            onTap: _resendCooldown > 0 ? null : _resendCode,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh,
                                  size: 14,
                                  color: _resendCooldown > 0
                                      ? const Color(0xFF9CA3AF)
                                      : const Color(0xFFE8A824),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _resendCooldown > 0
                                      ? 'Resend code in ${_resendCooldown}s'
                                      : 'Resend code',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _resendCooldown > 0
                                        ? const Color(0xFF9CA3AF)
                                        : const Color(0xFFE8A824),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFFD1D5DB),
                    ),
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
