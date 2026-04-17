import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'receipt.dart';
import 'env.dart';
import 'auth_service.dart';
import 'models/user.dart';
import 'departments.dart';
import 'models/trip.dart';

sealed class LoginResponse {}

class LoginSuccess extends LoginResponse {
  final String token;
  final AppUser user;
  final bool needsPassword;
  LoginSuccess({required this.token, required this.user, this.needsPassword = false});
}

class LoginNeedsRegistration extends LoginResponse {}

class LoginOtpSent extends LoginResponse {
  final String email;
  final String purpose; // "login" or "register"
  LoginOtpSent({required this.email, required this.purpose});
}

class AuthExpiredException implements Exception {
  final String message;
  AuthExpiredException([this.message = 'Token expired']);
  @override
  String toString() => message;
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

  // ─── Response Check ─────────────────────────────────

  void _checkResponse(http.Response res, {int expected = 200}) {
    if (res.statusCode == 401) {
      throw AuthExpiredException();
    }
    if (res.statusCode != expected) {
      final body = jsonDecode(res.body);
      final error = body['error'] ?? 'Request failed (${res.statusCode})';
      throw Exception(error);
    }
  }

  // ─── Auto Re-Auth ───────────────────────────────────

  bool _reAuthInProgress = false;

  Future<bool> _tryReAuth() async {
    if (_reAuthInProgress) return false;
    _reAuthInProgress = true;
    try {
      final creds = await AuthService.instance.getSavedCredentials();
      if (creds == null) return false;
      debugPrint('Token expired, attempting auto re-login for ${creds.email}');
      final res = await login(creds.email, password: creds.password, rememberMe: true);
      if (res is LoginSuccess) {
        await AuthService.instance.saveSession(res.token, res.user, remember: true);
        debugPrint('Auto re-login successful');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Auto re-login failed: $e');
      return false;
    } finally {
      _reAuthInProgress = false;
    }
  }

  // ─── Retry Wrapper ────────────────────────────────────

  Future<T> _withRetry<T>(Future<T> Function() fn) async {
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        return await fn();
      } on AuthExpiredException {
        // Token expired — try to re-login with saved credentials
        if (attempt < _maxRetries && await _tryReAuth()) {
          debugPrint('Re-auth succeeded, retrying request...');
          continue;
        }
        rethrow;
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
    String? password,
    String? name,
    String? department,
    String? departmentId,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/login');
    debugPrint('POST $uri');

    final body = <String, dynamic>{
      'email': email,
      'remember_me': rememberMe,
    };
    if (password != null && password.isNotEmpty) body['password'] = password;
    if (name != null) body['name'] = name;
    if (department != null) body['department'] = department;
    if (departmentId != null) body['department_id'] = departmentId;

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
            body: jsonEncode({'email': email, 'code': code, 'remember_me': rememberMe}))
        .timeout(_timeout);

    debugPrint('RESP ${res.statusCode}: ${res.body}');

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['error'] ?? 'Verification failed';
      throw Exception(error);
    }

    final data = jsonDecode(res.body);
    final user = AppUser.fromMap(data['user']);
    final token = data['token'] as String;
    final needsPassword = data['needs_password'] == true;

    await AuthService.instance.saveSession(token, user, remember: rememberMe);
    return LoginSuccess(token: token, user: user, needsPassword: needsPassword);
  }

  /// Set password for the authenticated user (max 8 characters).
  Future<void> setPassword(String password) async {
    final uri = Uri.parse('$baseUrl/auth/set-password');
    final headers = await _authHeaders();

    final res = await http
        .post(uri, headers: headers, body: jsonEncode({'password': password}))
        .timeout(_timeout);

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['error'] ?? 'Failed to set password';
      throw Exception(error);
    }
  }

  // ─── Password Reset ──────────────────────────────────

  Future<void> forgotPassword(String email) async {
    final uri = Uri.parse('$baseUrl/auth/forgot-password');
    final res = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}))
        .timeout(_timeout);

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['error'] ?? 'Request failed';
      throw Exception(error);
    }
  }

  Future<String> verifyResetOtp(String email, String code) async {
    final uri = Uri.parse('$baseUrl/auth/verify-reset-otp');
    final res = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'code': code}))
        .timeout(_timeout);

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['error'] ?? 'Verification failed';
      throw Exception(error);
    }

    final data = jsonDecode(res.body);
    return data['reset_token'] as String;
  }

  Future<void> resetPassword(String resetToken, String password) async {
    final uri = Uri.parse('$baseUrl/auth/reset-password');
    final res = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'reset_token': resetToken, 'password': password}))
        .timeout(_timeout);

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['error'] ?? 'Password reset failed';
      throw Exception(error);
    }
  }

  // ─── Change Password (authenticated) ─────────────────

  Future<void> changePassword(String currentPassword, String newPassword) async {
    final uri = Uri.parse('$baseUrl/auth/change-password');
    final headers = await _authHeaders();
    final res = await http
        .post(uri,
            headers: headers,
            body: jsonEncode({
              'current_password': currentPassword,
              'new_password': newPassword,
            }))
        .timeout(_timeout);

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['error'] ?? 'Failed to change password';
      throw Exception(error);
    }
  }

  // ─── Delete Account ─────────────────────────────────

  Future<void> deleteAccount() async {
    final uri = Uri.parse('$baseUrl/auth/delete-account');
    final headers = await _authHeaders();
    final res = await http.delete(uri, headers: headers).timeout(_timeout);

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['error'] ?? 'Failed to delete account';
      throw Exception(error);
    }
  }

  // ─── Trips ────────────────────────────────────────────

  Future<List<Trip>> fetchTrips({bool sync = false}) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/trips${sync ? '?sync=true' : ''}');
      final headers = await _authHeaders();

      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /trips${sync ? '?sync=true' : ''} ${res.statusCode}');
      _checkResponse(res);

      final List<dynamic> data = jsonDecode(res.body);
      return data.map((item) => Trip.fromMap(Map<String, dynamic>.from(item))).toList();
    });
  }

  Future<Trip> createTrip(Map<String, dynamic> data) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/trips');
      final headers = await _authHeaders();

      final res = await http
          .post(uri, headers: headers, body: jsonEncode(data))
          .timeout(_timeout);

      debugPrint('POST /trips ${res.statusCode}');
      _checkResponse(res, expected: 201);

      return Trip.fromMap(jsonDecode(res.body));
    });
  }

  Future<Trip> updateTrip(String tripId, Map<String, dynamic> updates) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/trips/$tripId');
      final headers = await _authHeaders();

      final res = await http
          .put(uri, headers: headers, body: jsonEncode(updates))
          .timeout(_timeout);

      debugPrint('PUT /trips/$tripId ${res.statusCode}');
      _checkResponse(res);

      return Trip.fromMap(jsonDecode(res.body));
    });
  }

  Future<Map<String, dynamic>> fetchTripDetail(String tripId) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/trips/$tripId');
      final headers = await _authHeaders();

      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /trips/$tripId ${res.statusCode}');
      _checkResponse(res);

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
  Future<({Receipt receipt, Trip? trip})> uploadReceipt(File image, {required String tripId, String paymentMethod = 'personal'}) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/expense');
      debugPrint('POST $uri (file=${image.path})');

      final token = await AuthService.instance.getToken();
      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', image.path))
        ..fields['trip_id'] = tripId
        ..fields['payment_method'] = paymentMethod;

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

  Future<Receipt> updateReceipt(String receiptId, Map<String, dynamic> fields) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/receipts/$receiptId');
      final token = await AuthService.instance.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final res = await http.patch(uri, headers: headers, body: jsonEncode(fields)).timeout(_timeout);
      if (res.statusCode != 200) {
        throw Exception('Update receipt failed: ${res.statusCode}');
      }
      return Receipt.fromMap(jsonDecode(res.body));
    });
  }

  Future<Receipt> updatePaymentMethod(String receiptId, String paymentMethod) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/receipts/$receiptId/payment-method');
      final token = await AuthService.instance.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final res = await http.patch(uri, headers: headers, body: jsonEncode({
        'payment_method': paymentMethod,
      })).timeout(_timeout);
      if (res.statusCode != 200) {
        throw Exception('Update payment method failed: ${res.statusCode}');
      }
      return Receipt.fromMap(jsonDecode(res.body));
    });
  }

  Future<Receipt> updateMealType(String receiptId, String mealType) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/receipts/$receiptId/meal-type');
      final headers = await _authHeaders();
      final res = await http
          .patch(uri, headers: headers, body: jsonEncode({'meal_type': mealType}))
          .timeout(_timeout);
      debugPrint('PATCH /receipts/$receiptId/meal-type ${res.statusCode}');
      if (res.statusCode != 200) {
        throw Exception('Update meal type failed: ${res.statusCode}');
      }
      return Receipt.fromMap(jsonDecode(res.body));
    });
  }

  // ── Alerts ──

  // ── Pending Reviews (admin-only) ──

  Future<List<Map<String, dynamic>>> fetchPendingReviews() async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/pending-reviews');
      final headers = await _authHeaders();
      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /pending-reviews ${res.statusCode}');
      if (res.statusCode != 200) throw Exception('Fetch pending reviews failed: ${res.statusCode}');
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    });
  }

  Future<Map<String, dynamic>> approvePendingReview(String reviewId) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/pending-reviews/$reviewId/approve');
      final headers = await _authHeaders();
      final res = await http.post(uri, headers: headers).timeout(_timeout);
      debugPrint('POST /pending-reviews/$reviewId/approve ${res.statusCode}');
      if (res.statusCode != 200) throw Exception('Approve failed: ${res.statusCode}');
      return Map<String, dynamic>.from(jsonDecode(res.body));
    });
  }

  Future<void> commentPendingReview(String reviewId, String comment) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/pending-reviews/$reviewId/comment');
      final headers = await _authHeaders();
      final res = await http.post(uri, headers: headers, body: jsonEncode({'comment': comment})).timeout(_timeout);
      debugPrint('POST /pending-reviews/$reviewId/comment ${res.statusCode}');
      if (res.statusCode != 200) throw Exception('Comment failed: ${res.statusCode}');
    });
  }

  // ── Traveler Alerts ──

  Future<List<Map<String, dynamic>>> fetchAlerts() async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/alerts');
      final headers = await _authHeaders();
      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /alerts ${res.statusCode}');
      if (res.statusCode != 200) {
        throw Exception('Fetch alerts failed: ${res.statusCode}');
      }
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    });
  }

  Future<Map<String, dynamic>> updateAlertStatus(String alertId, String status) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/alerts/$alertId/status');
      final headers = await _authHeaders();
      final res = await http
          .patch(uri, headers: headers, body: jsonEncode({'status': status}))
          .timeout(_timeout);
      debugPrint('PATCH /alerts/$alertId/status ${res.statusCode}');
      if (res.statusCode != 200) {
        throw Exception('Update alert status failed: ${res.statusCode}');
      }
      return Map<String, dynamic>.from(jsonDecode(res.body));
    });
  }

  Future<Map<String, dynamic>> approveReceipt(String receiptId, {String? comment}) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/receipts/$receiptId/approve');
      final headers = await _authHeaders();
      final body = <String, dynamic>{};
      if (comment != null && comment.trim().isNotEmpty) {
        body['comment'] = comment.trim();
      }
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_timeout);
      debugPrint('POST /receipts/$receiptId/approve ${res.statusCode}');
      if (res.statusCode != 200) {
        throw Exception('Approve receipt failed: ${res.statusCode}');
      }
      return Map<String, dynamic>.from(jsonDecode(res.body));
    });
  }

  Future<Map<String, dynamic>> addReceiptComment(String receiptId, String comment) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/receipts/$receiptId/comment');
      final headers = await _authHeaders();
      final res = await http
          .post(uri, headers: headers, body: jsonEncode({'comment': comment}))
          .timeout(_timeout);
      debugPrint('POST /receipts/$receiptId/comment ${res.statusCode}');
      if (res.statusCode != 201) {
        throw Exception('Add receipt comment failed: ${res.statusCode}');
      }
      return Map<String, dynamic>.from(jsonDecode(res.body));
    });
  }

  Future<Map<String, dynamic>> addTripComment(String tripId, String comment) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/trips/$tripId/comment');
      final headers = await _authHeaders();
      final res = await http
          .post(uri, headers: headers, body: jsonEncode({'comment': comment}))
          .timeout(_timeout);
      debugPrint('POST /trips/$tripId/comment ${res.statusCode}');
      if (res.statusCode != 201) {
        throw Exception('Add comment failed: ${res.statusCode}');
      }
      return Map<String, dynamic>.from(jsonDecode(res.body));
    });
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/users/search?q=${Uri.encodeComponent(query)}');
      final headers = await _authHeaders();
      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /users/search?q=$query ${res.statusCode}');
      if (res.statusCode != 200) return <Map<String, dynamic>>[];
      final list = jsonDecode(res.body) as List;
      return list.cast<Map<String, dynamic>>();
    });
  }

  Future<void> triggerAlertGeneration() async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/alerts/generate');
      final headers = await _authHeaders();
      final res = await http.post(uri, headers: headers).timeout(_timeout);
      debugPrint('POST /alerts/generate ${res.statusCode}');
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

  Future<List<Receipt>> fetchReceipts({String? tripId, String? userId}) async {
    return _withRetry(() async {
      final params = <String, String>{};
      if (tripId != null) params['trip_id'] = tripId;
      if (userId != null) params['user_id'] = userId;
      final uri = Uri.parse('$baseUrl/receipts').replace(queryParameters: params.isEmpty ? null : params);
      final headers = await _authHeaders();

      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /receipts ${res.statusCode}');
      _checkResponse(res);

      final List<dynamic> data = jsonDecode(res.body);
      return data.map((item) => Receipt.fromMap(Map<String, dynamic>.from(item))).toList();
    });
  }

  Future<Receipt> fetchReceiptById(String receiptId) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/receipts/$receiptId');
      final headers = await _authHeaders();
      final res = await http.get(uri, headers: headers).timeout(_timeout);
      debugPrint('GET /receipts/$receiptId ${res.statusCode}');
      _checkResponse(res);
      return Receipt.fromMap(Map<String, dynamic>.from(jsonDecode(res.body)));
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

  Future<({Receipt receipt, Trip? trip})> attachReceiptImage(
    File image, {required String receiptId}) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/receipts/$receiptId/attach');
      final token = await AuthService.instance.getToken();
      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', image.path));
      if (token != null) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      final streamed = await req.send().timeout(_timeout);
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode != 200) {
        throw Exception('Attach failed: ${res.statusCode} ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final receipt = Receipt.fromMap(Map<String, dynamic>.from(data['receipt'] ?? data));
      Trip? updatedTrip;
      if (data['trip'] != null) {
        updatedTrip = Trip.fromMap(Map<String, dynamic>.from(data['trip']));
      }
      return (receipt: receipt, trip: updatedTrip);
    });
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

  // ─── Departments ────────────────────────────────────────

  static List<String>? _cachedDepartments;
  static List<Department>? _cachedDeptObjects;

  Future<List<String>> fetchDepartmentOptions() async {
    if (_cachedDepartments != null) return _cachedDepartments!;

    final uri = Uri.parse('$baseUrl/departments');
    final res = await http.get(uri).timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('Failed to fetch departments');
    }

    final List<dynamic> data = jsonDecode(res.body);
    _cachedDepartments = data.cast<String>();
    return _cachedDepartments!;
  }

  /// Returns [Department] objects (name + code) for departments that
  /// exist in both the master PDF list and in Notion.
  Future<List<Department>> fetchDepartmentObjects() async {
    if (_cachedDeptObjects != null) return _cachedDeptObjects!;

    final names = await fetchDepartmentOptions();
    _cachedDeptObjects = resolvedDepartments(names);

    // If Notion has departments not in the master list, include them
    // with an empty code so they still appear.
    final resolvedNames = _cachedDeptObjects!.map((d) => d.name).toSet();
    for (final name in names) {
      if (!resolvedNames.contains(name)) {
        _cachedDeptObjects!.add(Department(name: name, code: ''));
      }
    }

    return _cachedDeptObjects!;
  }

  // ─── Report Summary (Gemini via backend) ───────────────

  Future<String> generateReportSummary(String prompt) async {
    final token = await AuthService.instance.getToken();
    final uri = Uri.parse('$baseUrl/report/summary');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'prompt': prompt}),
    ).timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw Exception('Report summary failed: ${res.statusCode}');
    }

    final data = jsonDecode(res.body);
    return data['summary'] as String;
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

  // ─── Profile Image ─────────────────────────────────────

  Future<String?> uploadProfileImage(File image) async {
    final uri = Uri.parse('$baseUrl/profile/image');
    final token = await AuthService.instance.getToken();
    final req = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', image.path));
    if (token != null) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    final streamed = await req.send().timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      throw Exception('Profile image upload failed: ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    return data['profile_image'] as String?;
  }

  Future<void> deleteProfileImage() async {
    final uri = Uri.parse('$baseUrl/profile/image');
    final headers = await _authHeaders();
    final res = await http.delete(uri, headers: headers).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Profile image delete failed: ${res.statusCode}');
    }
  }

  String profileImageUrl() => '$baseUrl/profile/image';

  String travelerImageUrl(String email) =>
      '$baseUrl/admin/traveler/${Uri.encodeComponent(email)}/image';

  /// Discard a trip and notify the traveler with an optional reason.
  Future<Map<String, dynamic>> discardTrip(String tripId, {String? comment}) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/trips/$tripId/discard');
      final headers = await _authHeaders();
      final body = <String, dynamic>{};
      if (comment != null && comment.trim().isNotEmpty) {
        body['comment'] = comment.trim();
      }
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_timeout);
      debugPrint('POST /trips/$tripId/discard ${res.statusCode}');
      if (res.statusCode != 200) {
        throw Exception('Discard trip failed: ${res.statusCode}');
      }
      return Map<String, dynamic>.from(jsonDecode(res.body));
    });
  }

  /// Approve a trip and optionally send a comment to the traveler.
  Future<Map<String, dynamic>> approveTrip(String tripId, {String? comment}) async {
    return _withRetry(() async {
      final uri = Uri.parse('$baseUrl/trips/$tripId/approve');
      final headers = await _authHeaders();
      final body = <String, dynamic>{};
      if (comment != null && comment.trim().isNotEmpty) {
        body['comment'] = comment.trim();
      }
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_timeout);
      debugPrint('POST /trips/$tripId/approve ${res.statusCode}');
      if (res.statusCode != 200) {
        throw Exception('Approve trip failed: ${res.statusCode}');
      }
      return Map<String, dynamic>.from(jsonDecode(res.body));
    });
  }
}
