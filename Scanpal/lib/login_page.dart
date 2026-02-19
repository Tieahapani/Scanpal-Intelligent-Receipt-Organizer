// 1. pubspec.yaml should have:
// dependencies:
//   google_sign_in: ^6.1.5

// 2. iOS setup already done:
//   ✅ GoogleService-Info.plist in ios/Runner/
//   ✅ REVERSED_CLIENT_ID in Info.plist

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'register_page.dart';
import 'entities.dart';
import 'reset_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginPage extends StatefulWidget {
  final bool clearFields;
  const LoginPage({super.key, this.clearFields = false});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _rememberMe = false;
  bool _isLoading = false;
  String? _loginError;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  @override
  void initState() {
    super.initState();
    if (widget.clearFields) {
      _usernameCtrl.clear();
      _passwordCtrl.clear();
    } else {
      _loadRememberedUser();
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedUser() async {
    final dir = await getApplicationDocumentsDirectory();
    final isar = Isar.getInstance() ??
        await Isar.open([UserEntitySchema], directory: dir.path);

    final rememberedUser =
        await isar.userEntitys.filter().rememberMeEqualTo(true).findFirst();

    if (rememberedUser != null) {
      setState(() {
        _usernameCtrl.text = rememberedUser.email.isNotEmpty
            ? rememberedUser.email
            : rememberedUser.username;
        _passwordCtrl.text = rememberedUser.password;
        _rememberMe = true;
      });
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _loginError = null;
    });

    final dir = await getApplicationDocumentsDirectory();
    final isar = Isar.getInstance() ??
        await Isar.open([UserEntitySchema], directory: dir.path);

    final input = _usernameCtrl.text.trim().toLowerCase();

    final user = await isar.userEntitys
        .filter()
        .group((q) => q.usernameEqualTo(input).or().emailEqualTo(input))
        .findFirst();

    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;

    if (user != null && user.password == _passwordCtrl.text.trim()) {
      await isar.writeTxn(() async {
        user.rememberMe = _rememberMe;
        user.isLoggedIn = true;
        await isar.userEntitys.put(user);
      });

      if (!mounted) return;
      print("✅ Login successful for user: ${user.username} (${user.email})");

      Navigator.pushReplacementNamed(context, '/home');
    } else {
      setState(() {
        _isLoading = false;
        _loginError = "Invalid username/email or password";
      });
    }
  }

  // ✅ Google Sign-In
  Future<void> _signInWithGoogle() async {
    try {
      setState(() {
        _isLoading = true;
        _loginError = null;
      });

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled
        setState(() => _isLoading = false);
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final isar = Isar.getInstance() ??
          await Isar.open([UserEntitySchema], directory: dir.path);

      // Check if user exists
      final existingUser = await isar.userEntitys
          .filter()
          .emailEqualTo(googleUser.email.toLowerCase())
          .findFirst();

      if (existingUser != null) {
        // User exists, log them in
        await isar.writeTxn(() async {
          existingUser.isLoggedIn = true;
          existingUser.rememberMe = true;
          await isar.userEntitys.put(existingUser);
        });

        if (!mounted) return;
        print("✅ Google Sign-In successful: ${existingUser.username}");
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        // New user, create account
        await isar.writeTxn(() async {
          final newUser = UserEntity()
            ..username = googleUser.email.split('@')[0].toLowerCase()
            ..email = googleUser.email.toLowerCase()
            ..fullName = googleUser.displayName ?? ''
            ..password = '' // No password for social login
            ..rememberMe = true
            ..isLoggedIn = true
            ..location = '';

          await isar.userEntitys.put(newUser);
          print("✅ New Google user registered: ${newUser.username}");
        });

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (error) {
      setState(() {
        _isLoading = false;
        _loginError = "Google Sign-In failed: $error";
      });
      print("❌ Google Sign-In error: $error");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "LOGIN",
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "TO CONTINUE",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 40),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _usernameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration:
                            _inputDecoration("Username or Email", Icons.person),
                        validator: (v) => v == null || v.isEmpty
                            ? "Enter username or email"
                            : null,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration("Password", Icons.lock),
                        validator: (v) =>
                            v == null || v.isEmpty ? "Enter password" : null,
                      ),
                      const SizedBox(height: 20),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                activeColor: Colors.white,
                                checkColor: Colors.blueAccent,
                                onChanged: (val) =>
                                    setState(() => _rememberMe = val ?? false),
                              ),
                              const Text(
                                "Remember Me",
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const ResetPage()),
                                );
                              },
                              child: const Text(
                                "Forgot Password?",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (_loginError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _loginError!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : ElevatedButton(
                              onPressed: _login,
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.blueAccent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                "LOG IN",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),

                      const SizedBox(height: 30),
                      Row(
                        children: const [
                          Expanded(child: Divider(color: Colors.white54, thickness: 1)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              "OR",
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.white54, thickness: 1)),
                        ],
                      ),
                      const SizedBox(height: 30),

                      // ✅ Google Sign-In Button
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blueAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.g_mobiledata, size: 32),
                        label: const Text(
                          "Continue with Google",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(height: 30),

                      RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: Colors.white70),
                          children: [
                            const TextSpan(text: "Don't have an account? "),
                            TextSpan(
                              text: "Register",
                              style: const TextStyle(
                                color: Colors.white,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const RegisterPage()),
                                  );
                                },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.white70),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.white),
      ),
      prefixIcon: Icon(icon, color: Colors.white),
    );
  }
}