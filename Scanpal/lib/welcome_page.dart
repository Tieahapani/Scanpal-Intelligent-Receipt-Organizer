import 'dart:async';
import 'package:flutter/material.dart';
import 'onboarding_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _controller.forward();

    // ⏳ Set a 6-second timer before navigating to OnboardingPage
    _timer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const OnboardingPage(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromARGB(255, 12, 93, 215), Color(0xFF42A5F5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: const _WelcomeCard(),
          ),
        ),
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    final headlineStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ) ??
        const TextStyle(
          fontSize: 32,
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 52),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: Colors.white.withOpacity(0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _ScannerIcon(),
          const SizedBox(height: 36),
          Text('Scanpal', style: headlineStyle),
        ],
      ),
    );
  }
}

class _ScannerIcon extends StatelessWidget {
  const _ScannerIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: CustomPaint(
        painter: _ScannerIconPainter(),
      ),
    );
  }
}

class _ScannerIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final outerGradient = RadialGradient(
      colors: [
        const Color(0xFFFFFFFF).withOpacity(0.95),
        const Color(0xFF90CAF9),
      ],
    );

    final outerPaint = Paint()
      ..shader =
          outerGradient.createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, outerPaint);

    final rimPaint = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08;
    canvas.drawCircle(center, radius * 0.72, rimPaint);

    final innerGlowPaint = Paint()
      ..color = const Color(0x6642A5F5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.34, innerGlowPaint);

    final innerRimPaint = Paint()
      ..color = const Color(0xD0FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05;
    canvas.drawCircle(center, radius * 0.34, innerRimPaint);

    final scannerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * 0.06
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double inset = size.width * 0.24;
    final double cornerLength = size.width * 0.22;

    // Top-left corner
    canvas.drawLine(
      Offset(inset, inset),
      Offset(inset + cornerLength, inset),
      scannerPaint,
    );
    canvas.drawLine(
      Offset(inset, inset),
      Offset(inset, inset + cornerLength),
      scannerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(size.width - inset - cornerLength, inset),
      Offset(size.width - inset, inset),
      scannerPaint,
    );
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(size.width - inset, inset + cornerLength),
      scannerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(inset + cornerLength, size.height - inset),
      scannerPaint,
    );
    canvas.drawLine(
      Offset(inset, size.height - inset - cornerLength),
      Offset(inset, size.height - inset),
      scannerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(size.width - inset - cornerLength, size.height - inset),
      Offset(size.width - inset, size.height - inset),
      scannerPaint,
    );
    canvas.drawLine(
      Offset(size.width - inset, size.height - inset - cornerLength),
      Offset(size.width - inset, size.height - inset),
      scannerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
