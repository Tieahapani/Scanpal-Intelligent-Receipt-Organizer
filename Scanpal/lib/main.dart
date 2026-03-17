import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'models/user.dart';
import 'login_page.dart';
import 'traveler_home_page.dart';
import 'admin_home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final auth = AuthService.instance;
  final token = await auth.getToken();
  final user = await auth.getUser();

  debugPrint('=== SESSION CHECK ===');
  debugPrint('Token present: ${token != null}');
  debugPrint('Token value: ${token?.substring(0, 10)}...');
  debugPrint('User present: ${user != null}');
  debugPrint('User email: ${user?.email}');
  debugPrint('=== END SESSION CHECK ===');

  runApp(MyApp(
    isLoggedIn: token != null && user != null,
    user: user,
  ));
}

class MyApp extends StatefulWidget {
  final bool isLoggedIn;
  final AppUser? user;

  const MyApp({super.key, required this.isLoggedIn, this.user});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ScanPal',
      theme: ThemeData.light(),
      home: widget.isLoggedIn
          ? (widget.user!.isAdmin
              ? AdminHomePage(user: widget.user!)
              : TravelerHomePage(user: widget.user!))
          : const LoginPage(),
    );
  }
}
