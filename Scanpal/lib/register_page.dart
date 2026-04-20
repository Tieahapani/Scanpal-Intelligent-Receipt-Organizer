import 'package:flutter/material.dart';
import 'api.dart';
import 'departments.dart';
import 'traveler_home_page.dart';
import 'otp_verify_page.dart';

class RegisterPage extends StatefulWidget {
  final String email;
  final bool rememberMe;

  const RegisterPage({super.key, required this.email, required this.rememberMe});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  late final TextEditingController _emailCtrl;
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isAdmin = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreeTerms = false;
  bool _showDeptDropdown = false;
  Department? _selectedDepartment;
  String? _error;

  static const _purple = Color(0xFF46166B);
  static const _gold = Color(0xFFE8A824);

  List<Department> _departments = [];

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.email);
    _fetchDepartments();
  }

  Future<void> _fetchDepartments() async {
    try {
      final api = APIService();
      final depts = await api.fetchDepartmentObjects();
      if (mounted) {
        setState(() => _departments = depts);
      }
    } catch (_) {
      // Departments will remain empty; user sees an empty dropdown
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  bool get _passwordsMatch =>
      _confirmPasswordCtrl.text.isEmpty ||
      _passwordCtrl.text == _confirmPasswordCtrl.text;

  bool get _isFormValid =>
      _nameCtrl.text.trim().isNotEmpty &&
      _emailCtrl.text.trim().isNotEmpty &&
      _emailCtrl.text.trim().contains('@') &&
      _selectedDepartment != null &&
      _passwordCtrl.text.isNotEmpty &&
      _confirmPasswordCtrl.text.isNotEmpty &&
      _passwordCtrl.text == _confirmPasswordCtrl.text &&
      _agreeTerms;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate() || !_isFormValid) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = APIService();
      final result = await api.login(
        _emailCtrl.text.trim(),
        rememberMe: widget.rememberMe,
        password: _passwordCtrl.text,
        name: _nameCtrl.text.trim(),
        department: _selectedDepartment?.name,
        departmentId: _selectedDepartment?.code,
      );

      if (!mounted) return;

      if (result is LoginOtpSent) {
        setState(() => _isLoading = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerifyPage(
              email: _emailCtrl.text.trim(),
              purpose: result.purpose,
              rememberMe: widget.rememberMe,
            ),
          ),
        );
      } else if (result is LoginSuccess) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => TravelerHomePage(user: result.user),
          ),
          (route) => false,
        );
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Registration failed. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefixIcon,
    Widget? suffixIcon,
    bool hasError = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      prefixIcon: Icon(prefixIcon, color: const Color(0xFF9CA3AF), size: 18),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: hasError ? Colors.red.shade400 : const Color(0xFFE5E7EB),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: hasError ? Colors.red.shade400 : _purple,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final password = _passwordCtrl.text;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),

                      // ASGo Logo
                      Center(
                        child: Image.asset(
                          'assets/asgo_logo.jpeg',
                          width: 192,
                          fit: BoxFit.contain,
                        ),
                      ),

                      // Tagline
                      const Center(
                        child: Text(
                          'Create your ASGo account',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Traveler / Admin Toggle
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            _buildToggle('Traveler', !_isAdmin),
                            const SizedBox(width: 4),
                            _buildToggle('Admin', _isAdmin),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Full Name
                      _buildLabel('FULL NAME'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        autocorrect: false,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                        decoration: _inputDecoration(
                          hint: 'Princy Ramani',
                          prefixIcon: Icons.person_outline_rounded,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Enter your full name';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // ASI Email
                      _buildLabel('ASI EMAIL ID'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                        decoration: _inputDecoration(
                          hint: 'your.name@asi.sfsu.edu',
                          prefixIcon: Icons.mail_outline_rounded,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Enter your ASI email';
                          if (!v.contains('@')) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Department Dropdown
                      _buildLabel('DEPARTMENT'),
                      const SizedBox(height: 6),
                      _buildDepartmentDropdown(),
                      const SizedBox(height: 14),

                      // Password
                      _buildLabel('CREATE PASSWORD'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                        decoration: _inputDecoration(
                          hint: 'Min. 8 characters',
                          prefixIcon: Icons.lock_outline_rounded,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: const Color(0xFF9CA3AF),
                              size: 18,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),

                      // Password strength bars
                      if (password.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: List.generate(4, (i) {
                            final level = (i + 1) * 3;
                            Color color;
                            if (password.length < level) {
                              color = const Color(0xFFE5E7EB);
                            } else if (password.length >= 12) {
                              color = Colors.green.shade400;
                            } else if (password.length >= 8) {
                              color = _gold;
                            } else {
                              color = Colors.red.shade400;
                            }
                            return Expanded(
                              child: Container(
                                height: 4,
                                margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],

                      // Password Requirements
                      const SizedBox(height: 8),
                      _buildPasswordRequirements(password),
                      const SizedBox(height: 14),

                      // Confirm Password
                      _buildLabel('CONFIRM PASSWORD'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _confirmPasswordCtrl,
                        obscureText: _obscureConfirm,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                        decoration: _inputDecoration(
                          hint: 'Re-enter your password',
                          prefixIcon: Icons.lock_outline_rounded,
                          hasError: !_passwordsMatch,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: const Color(0xFF9CA3AF),
                              size: 18,
                            ),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                      ),
                      if (!_passwordsMatch) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Passwords do not match',
                          style: TextStyle(fontSize: 12, color: Colors.red.shade500),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Terms Agreement
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _agreeTerms = !_agreeTerms),
                            child: Container(
                              width: 20,
                              height: 20,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                color: _agreeTerms ? _purple : Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _agreeTerms ? _purple : const Color(0xFFD1D5DB),
                                  width: 2,
                                ),
                              ),
                              child: _agreeTerms
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _agreeTerms = !_agreeTerms),
                              child: RichText(
                                text: const TextSpan(
                                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.5),
                                  children: [
                                    TextSpan(text: 'I agree to the '),
                                    TextSpan(
                                      text: 'Terms of Service',
                                      style: TextStyle(color: _purple),
                                    ),
                                    TextSpan(text: ' and '),
                                    TextSpan(
                                      text: 'Privacy Policy',
                                      style: TextStyle(color: _purple),
                                    ),
                                    TextSpan(text: ' of Associated Students'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

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
                        const SizedBox(height: 16),
                      ],

                      // Create Account Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading || !_isFormValid ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isFormValid ? _purple : const Color(0xFFD1D5DB),
                            foregroundColor: Colors.white,
                            elevation: _isFormValid ? 2 : 0,
                            shadowColor: _isFormValid
                                ? _purple.withValues(alpha: 0.3)
                                : Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            disabledBackgroundColor: const Color(0xFFD1D5DB),
                            disabledForegroundColor: Colors.white,
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
                                  'Create Account',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Login Link
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Already have an account? ',
                              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: const Text(
                                'Log In',
                                style: TextStyle(fontSize: 12, color: _gold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.only(bottom: 24, top: 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Powered by Associated Students',
                        style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'San Francisco State University',
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

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: Color(0xFF6B7280),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildToggle(String label, bool selected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _isAdmin = label == 'Admin'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _purple : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _purple.withValues(alpha: 0.4),
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

  Widget _buildDepartmentDropdown() {
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _showDeptDropdown = !_showDeptDropdown),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                const Icon(Icons.business_outlined, color: Color(0xFF9CA3AF), size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedDepartment?.name ?? 'Select your department',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedDepartment != null
                          ? const Color(0xFF111827)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _showDeptDropdown ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9CA3AF), size: 20),
                ),
              ],
            ),
          ),
        ),
        if (_showDeptDropdown)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                children: _departments.map((dept) {
                  final isSelected = _selectedDepartment == dept;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedDepartment = dept;
                        _showDeptDropdown = false;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: isSelected ? _purple.withValues(alpha: 0.05) : null,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              dept.name,
                              style: TextStyle(
                                fontSize: 14,
                                color: isSelected ? _purple : const Color(0xFF374151),
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check, size: 16, color: Color(0xFF46166B)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPasswordRequirements(String password) {
    final requirements = [
      ('Min. 8 characters', password.length >= 8),
      ('1 uppercase (A-Z)', RegExp(r'[A-Z]').hasMatch(password)),
      ('1 lowercase (a-z)', RegExp(r'[a-z]').hasMatch(password)),
      ('1 number (0-9)', RegExp(r'[0-9]').hasMatch(password)),
      ('1 special (!@#\$%)', RegExp(r'[!@#$%^&*()_+\-=\[\]{};:"|,.<>/?\\]').hasMatch(password)),
      ('No spaces', password.isNotEmpty && !password.contains(' ')),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 14, color: _gold),
              const SizedBox(width: 6),
              Text(
                'PASSWORD REQUIREMENTS',
                style: TextStyle(
                  fontSize: 10,
                  color: _gold,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: requirements.map((req) {
              final (label, met) = req;
              Widget icon;
              Color textColor;

              if (password.isEmpty) {
                icon = Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFD1D5DB)),
                  ),
                );
                textColor = const Color(0xFF6B7280);
              } else if (met) {
                icon = Icon(Icons.check, size: 14, color: Colors.green.shade500);
                textColor = Colors.green.shade600;
              } else {
                icon = Icon(Icons.close, size: 14, color: Colors.red.shade400);
                textColor = Colors.red.shade500;
              }

              return SizedBox(
                width: (MediaQuery.of(context).size.width - 96) / 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(fontSize: 10, color: textColor),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
