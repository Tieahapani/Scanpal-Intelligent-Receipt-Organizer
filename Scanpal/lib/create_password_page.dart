import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:isar/isar.dart';
import '/entities.dart';
import '/login_page.dart';
import 'package:path_provider/path_provider.dart';

class CreatePasswordPage extends StatefulWidget {
  final String email; 
  const CreatePasswordPage({super.key, required this.email});

  @override
  State<CreatePasswordPage> createState() => _CreatePasswordPageState();
}

class _CreatePasswordPageState extends State<CreatePasswordPage> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isHidden = true;
  bool _isLoading = false;

  // ✅ Password Reset Logic
  Future<void> _resetPassword() async {
    final password = _passwordCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (password.isEmpty || confirm.isEmpty) {
      _showError("Please fill in all fields");
      return;
    }

    if (password != confirm) {
      _showError("Passwords do not match");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uri = Uri.parse("http://192.168.1.69:5001/reset_password");
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": widget.email,
          "new_password": password,
        }),
      );

      // ✅ Always update local DB
      await _updateIsarPassword(password);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showSuccessDialog(
          title: "Password Reset Successful 🎉",
          message: "You can now log in with your new password.",
        );
      } else {
        _showSuccessDialog(
          title: "Password Updated Locally ✅",
          message: "We’ll sync when you're online.",
        );
      }
    } catch (e) {
      await _updateIsarPassword(password);

      _showSuccessDialog(
        title: "Password Saved Offline ✅",
        message: "We’ll sync when you're connected again.",
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ✅ Save password to Isar DB
  Future<void> _updateIsarPassword(String newPassword) async {
    final dir = await getApplicationDocumentsDirectory();
    final isar = Isar.getInstance() ??
        await Isar.open([UserEntitySchema], directory: dir.path);

    await isar.writeTxn(() async {
      final existingUser = await isar.userEntitys
          .filter()
          .emailEqualTo(widget.email.trim().toLowerCase())
          .findFirst();

      if (existingUser != null) {
        existingUser.password = newPassword;
        existingUser.isLoggedIn = false;
        existingUser.rememberMe = false;
        await isar.userEntitys.put(existingUser);
      } else {
        final newUser = UserEntity()
          ..fullName = ""
          ..location = ""
          ..username = widget.email.split('@').first
          ..email = widget.email.trim().toLowerCase()
          ..password = newPassword
          ..rememberMe = false
          ..isLoggedIn = false;
        await isar.userEntitys.put(newUser);
      }
    });
  }

  // ✅ Success Dialog (Beautiful Popup)
  void _showSuccessDialog({required String title, required String message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 50),
              const SizedBox(height: 15),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginPage(clearFields: true),
                    ),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 30, vertical: 12),
                ),
                child: const Text(
                  "Go to Login",
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

  // ❗ Small helper for inline errors
  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(height: 10),
              const Text(
                "Create new password 🔒",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Enter your new password below.",
                style: TextStyle(color: Colors.black87, fontSize: 15),
              ),
              const SizedBox(height: 30),
              _buildPasswordField("Password", _passwordCtrl),
              const SizedBox(height: 20),
              _buildPasswordField("Confirm Password", _confirmCtrl),
              const SizedBox(height: 40),
              Center(
                child: _isLoading
                    ? const CircularProgressIndicator(color: Color(0xFF1565C0))
                    : ElevatedButton(
                        onPressed: _resetPassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 80,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Continue",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      obscureText: _isHidden,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(
            _isHidden ? Icons.visibility_off_outlined : Icons.visibility,
          ),
          onPressed: () => setState(() => _isHidden = !_isHidden),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.black26),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF1565C0), width: 2),
        ),
      ),
    );
  }
}
