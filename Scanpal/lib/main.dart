import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'local_db.dart';
import 'entities.dart';
import 'login_page.dart';
import 'register_page.dart';
import 'home_screen.dart';
import 'onboarding_page.dart';
import 'welcome_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Open Isar before runApp
  final isar = await LocalDb.instance();

  // ✅ Check if a user has rememberMe = true
  final rememberedUser = await isar.userEntitys
      .filter()
      .rememberMeEqualTo(true)
      .findFirst();

  runApp(MyApp(
    autoLogin: rememberedUser != null,
  ));
}

class MyApp extends StatefulWidget {
  final bool autoLogin;

  const MyApp({super.key, required this.autoLogin});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // ✅ Theme state
  bool darkMode = false;

  // ✅ Called when user toggles theme in ProfilePage
  void toggleDarkMode(bool value) {
    setState(() {
      darkMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ScanPal',

      // ✅ Dynamic theme switching
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),

      // ✅ Home based on auto-login
      home: widget.autoLogin
          ? HomeScreen(
              darkMode: darkMode,
              onThemeChanged: toggleDarkMode,
            )
          : WelcomePage(),

      // ✅ Routes
      routes: {
        '/welcome': (_) => WelcomePage(),
        '/login': (_) => LoginPage(),
        '/register': (_) => RegisterPage(),
        '/onboarding': (_) => OnboardingPage(),

        // ✅ Home route also supports dark mode
        '/home': (_) => HomeScreen(
              darkMode: darkMode,
              onThemeChanged: toggleDarkMode,
            ),
      },
    );
  }
}
