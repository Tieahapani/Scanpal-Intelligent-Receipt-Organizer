import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'receipt.dart';
import 'env.dart';
import 'auth_service.dart';
import 'models/user.dart';
import 'models/trip.dart';

sealed class LoginResponse {}

class LoginSuccess extends LoginResponse {
  final String token;
  final AppUser user;
  LoginSuccess({required this.token, required this.user});
}

class LoginNeedsRegistration extends LoginResponse {}

class LoginOtpSent extends LoginResponse {
  final String email;
  final String purpose; // "login" or "register"
  LoginOtpSent({required this.email, required this.purpose});
}

class APIService {
  final String baseUrl;
  static const _timeout = Duration(seconds: 90);
  static const _maxRetries = 2;

  APIService({String? baseUrl}) : baseUrl = baseUrl ?? Env.baseUrl {
    debugPrint('APIService baseUrl = ${this.baseUrl}');
  }

  // ─── Auth Header ──────────────────────────────────────

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.instance.getToken();
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  // ─── Retry Wrapper ────────────────────────────────────

  Future<T> _withRetry<T>(Future<T> Function() fn) async {
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        return await fn();
      } on SocketException {
        if (attempt == _maxRetries) rethrow;
        debugPrint('Connection failed, retry ${attempt + 1}/$_maxRetries...');
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      } on TimeoutException {
        if (attempt == _maxRetries) rethrow;
        debugPrint('Timeout, retry ${attempt + 1}/$_maxRetries...');
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      } on HttpException {
        if (attempt == _maxRetries) rethrow;
        debugPrint('HTTP error, retry ${attempt + 1}/$_maxRetries...');
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    throw Exception('All retries failed');
  }

  // ─── Auth ─────────────────────────────────────────────

  Future<LoginResponse> login(
    String email, {
    bool rememberMe = true,
    String? name,
    String? department,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/login');
    debugPrint('POST $uri');

    final body = <String, dynamic>{'email': email};
    if (name != null) body['name'] = name;
    if (department != null) body['department'] = department;

    final res = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(_timeout);

    debugPrint('RESP ${res.statusCode}: ${res.body}');

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['error'] ?? 'Login failed';
      throw Exception(error);
    }

    final data = jsonDecode(res.body);

    // Backend signals that this email needs registration
    if (data['needs_registration'] == true) {
      return LoginNeedsRegistration();
    }

    // Backend sent an OTP
    if (data['otp_sent'] == true) {
      return LoginOtpSent(
        email: data['email'] as String,
        purpose: data['purpose'] as String,
      );
    }

    // Direct token response (backward compatibility)
    final user = AppUser.fromMap(data['user']);
    final token = data['token'] as String;

    await AuthService.instance.saveSession(token, user, remember: rememberMe);

    return LoginSuccess(token: token, user: user);
  }

  /// Verify OTP code. Returns LoginSuccess with token and user on success.
  Future<LoginSuccess> verifyOtp(String email, String code, {bool rememberMe = true}) async {
    final uri = Uri.parse('$baseUrl/auth/verify-otp');
    debugPrint('POST $uri');

    final res = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'code': code}))
        .timeout(_timeout);

    debugPrint('RESP ${res.statusCode}: ${res.body}');

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['error'] ?? 'Verification failed';
      throw Exception(error);
    }

    final data = jsonDecode(res.body);
    final user = AppUser.fromMap(data['user']);
    final token = data['token'] as String;

    await AuthService.instance.saveSession(token, user, remember: rememberMe);
    return LoginSuccess(token: token, user: user);
  }

  // ─── Trips ────────────────────────────────────────────

  Future<List<Trip>> fetchTrips({bool sync = false}) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/trips${sync ? '?sync=true' : ''}');
      final headers = await _authHeaders();

      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /trips${sync ? '?sync=true' : ''} ${res.statusCode}');

      if (res.statusCode != 200) {
        throw Exception('Failed to fetch trips: ${res.statusCode}');
      }

      final List<dynamic> data = jsonDecode(res.body);
      return data.map((item) => Trip.fromMap(Map<String, dynamic>.from(item))).toList();
    });
  }

  Future<Trip> createTrip({
    required String tripPurpose,
    required String destination,
    DateTime? departureDate,
    DateTime? returnDate,
  }) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/trips');
      final headers = await _authHeaders();

      final body = <String, dynamic>{
        'trip_purpose': tripPurpose,
        'destination': destination,
        if (departureDate != null) 'departure_date': departureDate.toIso8601String(),
        if (returnDate != null) 'return_date': returnDate.toIso8601String(),
      };

      final res = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_timeout);

      debugPrint('POST /trips ${res.statusCode}');

      if (res.statusCode != 201) {
        final error = jsonDecode(res.body)['error'] ?? 'Failed to create trip';
        throw Exception(error);
      }

      return Trip.fromMap(jsonDecode(res.body));
    });
  }

  Future<Map<String, dynamic>> fetchTripDetail(String tripId) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/trips/$tripId');
      final headers = await _authHeaders();

      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /trips/$tripId ${res.statusCode}');

      if (res.statusCode != 200) {
        throw Exception('Failed to fetch trip detail: ${res.statusCode}');
      }

      return jsonDecode(res.body);
    });
  }

  Future<Map<String, dynamic>> triggerSync() async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/trips/sync');
      final headers = await _authHeaders();

      final res = await http.post(uri, headers: headers).timeout(_timeout);
      debugPrint('POST /trips/sync ${res.statusCode}');

      if (res.statusCode != 200) {
        throw Exception('Sync failed: ${res.statusCode}');
      }

      return jsonDecode(res.body);
    });
  }

  // ─── Receipts ─────────────────────────────────────────

  /// Uploads a receipt and returns both the receipt and (optionally) the updated trip.
  Future<({Receipt receipt, Trip? trip})> uploadReceipt(File image, {required String tripId}) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/expense');
      debugPrint('POST $uri (file=${image.path})');

      final token = await AuthService.instance.getToken();
      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', image.path))
        ..fields['trip_id'] = tripId;

      if (token != null) {
        req.headers['Authorization'] = 'Bearer $token';
      }

      final streamed = await req.send().timeout(_timeout);
      final res = await http.Response.fromStream(streamed);
      debugPrint('RESP ${res.statusCode}: ${res.body}');

      if (res.statusCode != 200) {
        throw Exception('Expense parse failed: ${res.statusCode} ${res.reasonPhrase}\n${res.body}');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final receiptMap = data['receipt'] ?? data;
      final receipt = Receipt.fromMap(Map<String, dynamic>.from(receiptMap));

      Trip? updatedTrip;
      if (data['trip'] != null) {
        updatedTrip = Trip.fromMap(Map<String, dynamic>.from(data['trip']));
      }

      return (receipt: receipt, trip: updatedTrip);
    });
  }

  Future<Map<String, dynamic>> confirmCategory(String receiptId, String travelCategory) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/receipts/$receiptId/confirm');
      final headers = await _authHeaders();

      final res = await http
          .post(uri,
              headers: headers,
              body: jsonEncode({'travel_category': travelCategory}))
          .timeout(_timeout);

      debugPrint('POST /receipts/$receiptId/confirm ${res.statusCode}');

      if (res.statusCode != 200) {
        throw Exception('Confirm failed: ${res.statusCode}');
      }

      return jsonDecode(res.body);
    });
  }

  Future<List<Receipt>> fetchReceipts({String? tripId}) async {
    return _withRetry(() async {
      var url = '$baseUrl/receipts';
      if (tripId != null) url += '?trip_id=$tripId';
      final uri = Uri.parse(url);
      final headers = await _authHeaders();

      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /receipts ${res.statusCode}');

      if (res.statusCode != 200) {
        throw Exception('Failed to fetch receipts: ${res.statusCode}');
      }

      final List<dynamic> data = jsonDecode(res.body);
      return data.map((item) => Receipt.fromMap(Map<String, dynamic>.from(item))).toList();
    });
  }

  Future<bool> deleteTrip(String tripId) async {
    try {
      final uri = Uri.parse('$baseUrl/trips/$tripId');
      final headers = await _authHeaders();
      final res = await http.delete(uri, headers: headers).timeout(_timeout);
      debugPrint('DELETE /trips/$tripId ${res.statusCode}');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Failed to delete trip: $e');
      return false;
    }
  }

  Future<bool> deleteReceipt(String receiptId) async {
    try {
      final uri = Uri.parse('$baseUrl/receipts/$receiptId');
      final headers = await _authHeaders();
      final res = await http.delete(uri, headers: headers).timeout(_timeout);
      debugPrint('DELETE /receipts/$receiptId ${res.statusCode}');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Failed to delete receipt: $e');
      return false;
    }
  }

  String receiptImageUrl(String receiptId) {
    return '$baseUrl/receipts/$receiptId/image';
  }

  // ─── Admin ────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchDepartments() async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/admin/departments');
      final headers = await _authHeaders();

      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /admin/departments ${res.statusCode}');

      if (res.statusCode != 200) {
        throw Exception('Failed to fetch departments: ${res.statusCode}');
      }

      final List<dynamic> data = jsonDecode(res.body);
      return data.map((item) => Map<String, dynamic>.from(item)).toList();
    });
  }

  Future<Map<String, dynamic>> fetchOrgAnalytics() async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/admin/analytics');
      final headers = await _authHeaders();

      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /admin/analytics ${res.statusCode}');

      if (res.statusCode != 200) {
        throw Exception('Failed to fetch analytics: ${res.statusCode}');
      }

      return jsonDecode(res.body);
    });
  }

  Future<List<Map<String, dynamic>>> fetchAllTravelers() async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/admin/travelers');
      final headers = await _authHeaders();

      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /admin/travelers ${res.statusCode}');

      if (res.statusCode != 200) {
        throw Exception('Failed to fetch travelers: ${res.statusCode}');
      }

      final List<dynamic> data = jsonDecode(res.body);
      return data.map((item) => Map<String, dynamic>.from(item)).toList();
    });
  }

  // ─── Health ───────────────────────────────────────────

  Future<bool> isServerAlive() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
