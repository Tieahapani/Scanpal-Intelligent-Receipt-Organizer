import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/user.dart';

class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'user_data';
  static const _rememberKey = 'remember_me';
  static const _savedEmailKey = 'saved_email';
  static const _savedPasswordKey = 'saved_password';
  static const _lastRoleKey = 'last_role';

  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();
  AuthService._();

  String? _cachedToken;
  AppUser? _cachedUser;

  /// Save session. If [remember] is true, persist to disk so the user
  /// stays logged in across app restarts. Otherwise keep in memory only.
  Future<void> saveSession(String token, AppUser user, {bool remember = true}) async {
    _cachedToken = token;
    _cachedUser = user;

    final prefs = await SharedPreferences.getInstance();
    if (remember) {
      debugPrint('AuthService.saveSession: persisting to disk for ${user.email}');
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_userKey, jsonEncode(user.toMap()));
      await prefs.setBool(_rememberKey, true);
    } else {
      debugPrint('AuthService.saveSession: memory-only for ${user.email}');
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
      await prefs.setBool(_rememberKey, false);
    }
  }

  /// Save login credentials locally so they auto-fill next time.
  Future<void> saveCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedEmailKey, email);
    await prefs.setString(_savedPasswordKey, password);
    debugPrint('AuthService: saved credentials for $email');
  }

  /// Load saved credentials. Returns null if none saved.
  Future<({String email, String password})?> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_savedEmailKey);
    final password = prefs.getString(_savedPasswordKey);
    if (email != null && password != null) {
      return (email: email, password: password);
    }
    return null;
  }

  /// Clear saved credentials (when Remember Me is unchecked).
  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedEmailKey);
    await prefs.remove(_savedPasswordKey);
  }

  Future<String?> getToken() async {
    if (_cachedToken != null) {
      return _cachedToken;
    }
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_tokenKey);
    return _cachedToken;
  }

  Future<void> updateUser(AppUser user) async {
    _cachedUser = user;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_userKey)) {
      await prefs.setString(_userKey, jsonEncode(user.toMap()));
    }
  }

  Future<AppUser?> getUser() async {
    if (_cachedUser != null) {
      return _cachedUser;
    }
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_userKey);
    if (json == null) return null;
    _cachedUser = AppUser.fromMap(jsonDecode(json));
    return _cachedUser;
  }

  Future<bool> get isLoggedIn async => (await getToken()) != null;

  Future<bool> getRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberKey) ?? false;
  }

  /// Save which role (traveler/admin) was last used for login.
  Future<void> saveLastRole(bool isAdmin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRoleKey, isAdmin ? 'admin' : 'traveler');
  }

  /// Get the last used role. Returns true if admin, false if traveler.
  Future<bool> getLastRoleIsAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastRoleKey) == 'admin';
  }

  /// Logout: clear session token but keep saved credentials
  /// so they auto-fill on the login page.
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    // Don't remove _rememberKey, _savedEmailKey, _savedPasswordKey
    // so credentials auto-fill after logout
    _cachedToken = null;
    _cachedUser = null;
  }

  /// Full clear: remove everything including saved credentials.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_rememberKey);
    await prefs.remove(_savedEmailKey);
    await prefs.remove(_savedPasswordKey);
    _cachedToken = null;
    _cachedUser = null;
  }
}
