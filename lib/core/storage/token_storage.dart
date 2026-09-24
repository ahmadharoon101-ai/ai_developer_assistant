import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens live in the platform keystore/keychain, never in plain prefs.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _tokenKey = 'access_token';
  static const _userKey = 'user_json';

  Future<String?> readAccessToken() => _s.read(key: _tokenKey);
  Future<void> writeAccessToken(String token) =>
      _s.write(key: _tokenKey, value: token);

  Future<Map<String, dynamic>?> readUser() async {
    final raw = await _s.read(key: _userKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> writeUser(Map<String, dynamic> user) =>
      _s.write(key: _userKey, value: jsonEncode(user));

  Future<void> clear() async {
    await _s.delete(key: _tokenKey);
    await _s.delete(key: _userKey);
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
