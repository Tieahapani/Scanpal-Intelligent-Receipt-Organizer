// lib/env.dart
class Env {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.143.96.183:5001',
  );
}



