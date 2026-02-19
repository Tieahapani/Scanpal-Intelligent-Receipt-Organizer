import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'login_page.dart';
import 'local_db.dart';
import 'entities.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:isar/isar.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _isLoading = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _locationCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // ✅ Google Sign-In
  Future<void> _signInWithGoogle() async {
    try {
      setState(() => _isLoading = true);

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
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
        // User exists, just log them in
        await isar.writeTxn(() async {
          existingUser.isLoggedIn = true;
          existingUser.rememberMe = true;
          await isar.userEntitys.put(existingUser);
        });

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        // New user, create account
        await isar.writeTxn(() async {
          final newUser = UserEntity()
            ..username = googleUser.email.split('@')[0].toLowerCase()
            ..email = googleUser.email.toLowerCase()
            ..fullName = googleUser.displayName ?? ''
            ..password = ''
            ..rememberMe = true
            ..isLoggedIn = true
            ..location = '';

          await isar.userEntitys.put(newUser);
        });

        if (!mounted) return;
        _showSuccessDialog(googleUser.displayName ?? 'User');
      }
    } catch (error) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-In failed: $error')),
        );
      }
    }
  }

  void _showSuccessDialog(String name) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF1565C0),
                Color(0xFF42A5F5),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 15),
              Text(
                "Welcome, $name! 🎉",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                "Your account has been created successfully.",
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/home');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                ),
                child: const Text(
                  "Get Started",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                  "SIGN UP",
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "CREATE YOUR ACCOUNT",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 30),

                // Traditional Form
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildField(
                        controller: _fullNameCtrl,
                        label: "Full Name",
                        icon: Icons.badge,
                        validator: (v) =>
                            v == null || v.isEmpty ? "Enter full name" : null,
                      ),
                      const SizedBox(height: 20),
                      _buildField(
                        controller: _locationCtrl,
                        label: "Location",
                        icon: Icons.location_on,
                        validator: (v) =>
                            v == null || v.isEmpty ? "Enter location" : null,
                      ),
                      const SizedBox(height: 20),
                      _buildField(
                        controller: _usernameCtrl,
                        label: "Username",
                        icon: Icons.person,
                        validator: (v) =>
                            v == null || v.isEmpty ? "Enter username" : null,
                      ),
                      const SizedBox(height: 20),
                      _buildField(
                        controller: _emailCtrl,
                        label: "Email",
                        icon: Icons.email,
                        validator: (v) {
                          if (v == null || v.isEmpty) return "Enter email";
                          final emailRegex =
                              RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,4}$');
                          if (!emailRegex.hasMatch(v)) {
                            return "Enter a valid email address";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      _buildField(
                        controller: _passwordCtrl,
                        label: "Password (min 8 chars)",
                        icon: Icons.lock,
                        obscure: true,
                        validator: (v) {
                          if (v == null || v.isEmpty) return "Enter password";
                          if (v.length < 8) {
                            return "Password must be at least 8 chars";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      _buildField(
                        controller: _confirmPasswordCtrl,
                        label: "Confirm Password",
                        icon: Icons.lock_outline,
                        obscure: true,
                        validator: (v) {
                          if (v != _passwordCtrl.text) {
                            return "Passwords don't match";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 40),

                      ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                if (_formKey.currentState!.validate()) {
                                  setState(() => _isLoading = true);

                                  final isar = await LocalDb.instance();
                                  await isar.writeTxn(() async {
                                    final newUser = UserEntity()
                                      ..username =
                                          _usernameCtrl.text.trim().toLowerCase()
                                      ..email = _emailCtrl.text.trim().toLowerCase()
                                      ..fullName = _fullNameCtrl.text.trim()
                                      ..location = _locationCtrl.text.trim()
                                      ..password = _passwordCtrl.text.trim()
                                      ..rememberMe = false
                                      ..isLoggedIn = false;

                                    await isar.userEntitys.put(newUser);
                                    print(
                                        "✅ Registered new user: ${newUser.username}");
                                  });

                                  setState(() => _isLoading = false);

                                  if (!mounted) return;

                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (_) => Dialog(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 28),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF1565C0),
                                              Color(0xFF42A5F5),
                                            ],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.check_circle_outline,
                                              color: Colors.white,
                                              size: 48,
                                            ),
                                            const SizedBox(height: 15),
                                            const Text(
                                              "Account Created!",
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 10),
                                            const Text(
                                              "You have successfully signed up.",
                                              style: TextStyle(
                                                fontSize: 15,
                                                color: Colors.white70,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 28),
                                            ElevatedButton(
                                              onPressed: () {
                                                Navigator.pushReplacement(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const LoginPage(),
                                                  ),
                                                );
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.white,
                                                foregroundColor:
                                                    Colors.blueAccent,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 30,
                                                        vertical: 12),
                                              ),
                                              child: const Text(
                                                "Login to Continue",
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blueAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.blueAccent,
                              )
                            : const Text(
                                "SIGN UP",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                      const SizedBox(height: 20),

                      // ✅ Register Link
                      RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: Colors.white70),
                          children: [
                            const TextSpan(text: "Already have an account? "),
                            TextSpan(
                              text: "Login",
                              style: const TextStyle(
                                color: Colors.white,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginPage(),
                                    ),
                                  );
                                },
                            ),
                          ],
                        ),
                      ),

                      // ✅ Google Sign-In at Bottom
                      const SizedBox(height: 30),
                      Row(
                        children: const [
                          Expanded(
                              child: Divider(color: Colors.white54, thickness: 1)),
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
                          Expanded(
                              child: Divider(color: Colors.white54, thickness: 1)),
                        ],
                      ),
                      const SizedBox(height: 30),

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
                          "sign up with Google",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white70),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.grey),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.grey, width: 2),
        ),
        errorStyle: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
        ),
        prefixIcon: Icon(icon, color: Colors.white),
      ),
      validator: validator,
    );
  }
}