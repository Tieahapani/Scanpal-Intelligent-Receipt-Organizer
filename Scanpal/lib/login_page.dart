import 'package:flutter/material.dart';
import 'api.dart';
import 'auth_service.dart';
import 'traveler_home_page.dart';
import 'admin_home_page.dart';
import 'register_page.dart';
import 'otp_verify_page.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;
  bool _isAdminLogin = false;
  bool _obscurePassword = true;
  String? _error;
  bool _passwordError = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final auth = AuthService.instance;
    final lastRoleIsAdmin = await auth.getLastRoleIsAdmin();
    final remembered = await auth.getRememberMe();
    if (mounted) {
      setState(() => _isAdminLogin = lastRoleIsAdmin);
    }
    if (remembered) {
      final creds = await auth.getSavedCredentials();
      if (creds != null && mounted) {
        setState(() {
          _emailCtrl.text = creds.email;
          _passwordCtrl.text = creds.password;
          _rememberMe = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = APIService();
      final password = _passwordCtrl.text;
      final result = await api.login(
        _emailCtrl.text.trim(),
        rememberMe: _rememberMe,
        password: password.isNotEmpty ? password : null,
        requestedRole: _isAdminLogin ? 'admin' : 'traveler',
      );

      if (!mounted) return;

      // Save role and credentials
      final auth = AuthService.instance;
      await auth.saveLastRole(_isAdminLogin);
      if (_rememberMe && password.isNotEmpty) {
        await auth.saveCredentials(_emailCtrl.text.trim(), password);
      } else if (!_rememberMe) {
        await auth.clearCredentials();
      }

      switch (result) {
        case LoginSuccess():
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => result.user.isAdmin
                  ? AdminHomePage(user: result.user)
                  : TravelerHomePage(user: result.user),
            ),
            (route) => false,
          );
        case LoginNeedsRegistration():
          setState(() => _isLoading = false);
          if (_isAdminLogin) {
            setState(() => _error = 'This email is not authorized for admin access.');
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RegisterPage(
                email: _emailCtrl.text.trim(),
                rememberMe: _rememberMe,
              ),
            ),
          );
        case LoginOtpSent():
          setState(() => _isLoading = false);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OtpVerifyPage(
                email: result.email,
                purpose: result.purpose,
                rememberMe: _rememberMe,
              ),
            ),
          );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      final isPasswordError = msg.toLowerCase().contains('incorrect password');
      setState(() {
        _isLoading = false;
        _error = msg;
        _passwordError = isPasswordError;
      });
      if (isPasswordError) {
        _shakeController.forward(from: 0);
      }
    }
  }

  bool get _canLogin => _emailCtrl.text.trim().isNotEmpty && _passwordCtrl.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // ASGo Logo
                Image.asset(
                  'assets/asgo_logo.jpeg',
                  width: 256,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 0),
                const Text(
                  'Associated Students \u00B7 SF State University',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 32),

                // Traveler / Admin toggle
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      _buildToggle('Traveler', !_isAdminLogin),
                      const SizedBox(width: 4),
                      _buildToggle('Admin', _isAdminLogin),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Form
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Email label
                      const Text(
                        'ASI EMAIL ID',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B7280),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF111827),
                        ),
                        decoration: InputDecoration(
                          hintText: _isAdminLogin
                              ? 'admin@asi.sfsu.edu'
                              : 'princy.ramani@asi.sfsu.edu',
                          hintStyle: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.mail_outline_rounded,
                            color: Color(0xFF9CA3AF),
                            size: 18,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 16,
                          ),
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
                            borderSide: const BorderSide(
                              color: Color(0xFF46166B),
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.red, width: 1.5),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Enter your ASI email';
                          }
                          if (!v.contains('@')) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Password label
                      const Text(
                        'PASSWORD',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B7280),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedBuilder(
                        animation: _shakeAnimation,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(_shakeAnimation.value, 0),
                          child: child,
                        ),
                        child: TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePassword,
                          onChanged: (_) => setState(() {
                            _passwordError = false;
                            _error = null;
                          }),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF111827),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter your password',
                            hintStyle: const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.lock_outline_rounded,
                              color: _passwordError ? Colors.red.shade400 : const Color(0xFF9CA3AF),
                              size: 18,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: const Color(0xFF9CA3AF),
                                size: 18,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                            filled: true,
                            fillColor: _passwordError ? Colors.red.shade50 : const Color(0xFFF9FAFB),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: _passwordError ? Colors.red.shade300 : const Color(0xFFE5E7EB),
                                width: _passwordError ? 1.5 : 1,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: _passwordError ? Colors.red : const Color(0xFF46166B),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Password requirements warning (hide for returning users)
                      if (!_rememberMe) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8A824).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFE8A824).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.warning_amber_rounded,
                                size: 14,
                                color: Color(0xFFE8A824),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: RichText(
                                text: const TextSpan(
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF4B5563),
                                    height: 1.5,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'Password must: ',
                                      style: TextStyle(color: Color(0xFFE8A824)),
                                    ),
                                    TextSpan(
                                      text: 'be at least 8 characters, include 1 uppercase, 1 lowercase, 1 number & 1 special character (!@#\$%)',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ],
                      const SizedBox(height: 16),

                      // Remember me row
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _rememberMe = !_rememberMe),
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: _rememberMe ? const Color(0xFF46166B) : Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _rememberMe ? const Color(0xFF46166B) : const Color(0xFFD1D5DB),
                                  width: 2,
                                ),
                              ),
                              child: _rememberMe
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() => _rememberMe = !_rememberMe),
                            child: const Text(
                              'Remember me',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'Skip verification next time',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF9CA3AF),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
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

                      // Log In button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _canLogin
                                ? const Color(0xFF46166B)
                                : const Color(0xFFD1D5DB),
                            foregroundColor: Colors.white,
                            elevation: _canLogin ? 2 : 0,
                            shadowColor: _canLogin
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
                                  'Log In',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Forgot password
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ForgotPasswordPage(
                                  initialEmail: _emailCtrl.text.trim(),
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            'Forgot your password?',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFE8A824),
                            ),
                          ),
                        ),
                      ),

                      // Register link
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Don't have an account? ",
                              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RegisterPage(
                                      email: _emailCtrl.text.trim(),
                                      rememberMe: _rememberMe,
                                    ),
                                  ),
                                );
                              },
                              child: const Text(
                                'Register',
                                style: TextStyle(fontSize: 12, color: Color(0xFFE8A824)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                // Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE8A824),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Powered by Associated Students',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE8A824),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'San Francisco State University',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFFD1D5DB),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggle(String label, bool selected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _isAdminLogin = label == 'Admin';
          _error = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF46166B) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF46166B).withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : const Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }
}
