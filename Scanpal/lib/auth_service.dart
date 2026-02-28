import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/user.dart';

class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'user_data';
  static const _rememberKey = 'remember_me';

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

    if (remember) {
      debugPrint('AuthService.saveSession: persisting to disk for ${user.email}');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_userKey, jsonEncode(user.toMap()));
      await prefs.setBool(_rememberKey, true);

      // Verify write
      final ok = prefs.getString(_tokenKey) != null;
      debugPrint('AuthService.saveSession: verified write=$ok');
    } else {
      debugPrint('AuthService.saveSession: memory-only for ${user.email}');
      // Clear any old persisted session
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
      await prefs.setBool(_rememberKey, false);
    }
  }

  Future<String?> getToken() async {
    if (_cachedToken != null) {
      debugPrint('AuthService.getToken: returning cached token');
      return _cachedToken;
    }
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_tokenKey);
    debugPrint('AuthService.getToken: from disk=${_cachedToken != null}');
    return _cachedToken;
  }

  Future<AppUser?> getUser() async {
    if (_cachedUser != null) {
      debugPrint('AuthService.getUser: returning cached user');
      return _cachedUser;
    }
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_userKey);
    debugPrint('AuthService.getUser: from disk=${json != null}');
    if (json == null) return null;
    _cachedUser = AppUser.fromMap(jsonDecode(json));
    return _cachedUser;
  }

  Future<bool> get isLoggedIn async => (await getToken()) != null;

  /// Whether the user previously chose "Remember me".
  Future<bool> getRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberKey) ?? false;
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_rememberKey);
    _cachedToken = null;
    _cachedUser = null;
  }
}
