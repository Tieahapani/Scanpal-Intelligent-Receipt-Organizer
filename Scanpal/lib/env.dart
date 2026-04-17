// lib/env.dart
class Env {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://asgo-associated-students-travel.onrender.com',
  );
}




