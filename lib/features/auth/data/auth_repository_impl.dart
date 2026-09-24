import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/token_storage.dart';
import '../domain/auth_repository.dart';

/// Talks to the FastAPI backend.
/// Login response: {"access_token": "...", "user": {"id","name","email"}}
class RemoteAuthRepository implements AuthRepository {
  RemoteAuthRepository(this._dio, this._storage);
  final Dio _dio;
  final TokenStorage _storage;

  Future<AuthUser> _persist(dynamic data) async {
    final map = data as Map<String, dynamic>;
    final user = AuthUser.fromJson(map['user'] as Map<String, dynamic>);
    await _storage.writeAccessToken(map['access_token'] as String);
    await _storage.writeUser(user.toJson());
    return user;
  }

  @override
  Future<AuthUser?> restoreSession() async {
    try {
      final token = await _storage.readAccessToken();
      if (token == null) return null;
      final res = await _dio.get<dynamic>(ApiConstants.me);
      final user = AuthUser.fromJson(res.data as Map<String, dynamic>);
      await _storage.writeUser(user.toJson());
      return user;
    } catch (e) {
      final err = e is DioException ? e.error : null;
      if (err is ApiException && err.isUnauthorized) await _storage.clear();
      return null;
    }
  }

  @override
  Future<AuthUser> login({required String email, required String password}) async {
    try {
      final res = await _dio.post<dynamic>(ApiConstants.login,
          data: {'email': email.trim(), 'password': password});
      return _persist(res.data);
    } catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<void> register(
      {required String name, required String email, required String password}) async {
    try {
      // The backend returns a session too, but we deliberately don't store it:
      // the person is sent to the login screen to sign in explicitly.
      await _dio.post<dynamic>(ApiConstants.register, data: {
        'full_name': name.trim(),
        'email': email.trim(),
        'password': password,
      });
    } catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<AuthUser> updateProfile(String name) async {
    try {
      final res = await _dio.put<dynamic>(ApiConstants.profile, data: {'name': name.trim()});
      final user = AuthUser.fromJson(res.data as Map<String, dynamic>);
      await _storage.writeUser(user.toJson());
      return user;
    } catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<void> changePassword(String current, String next) async {
    try {
      final res = await _dio.post<dynamic>(ApiConstants.password,
          data: {'current_password': current, 'new_password': next});
      await _storage
          .writeAccessToken((res.data as Map<String, dynamic>)['access_token'] as String);
    } catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<void> logoutEverywhere() async {
    try {
      await _dio.post<dynamic>(ApiConstants.logoutAll);
    } catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<void> logout() => _storage.clear();

  @override
  Future<void> clearLocalSession() => _storage.clear();

  @override
  Future<ForgotPasswordResult> forgotPassword(String email) async {
    try {
      final res =
          await _dio.post<dynamic>(ApiConstants.forgotPassword, data: {'email': email.trim()});
      final j = res.data as Map<String, dynamic>;
      return ForgotPasswordResult(message: j['message'] as String, devCode: j['dev_code'] as String?);
    } catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<void> resetPassword({required String code, required String newPassword}) async {
    try {
      await _dio.post<dynamic>(ApiConstants.resetPassword,
          data: {'code': code.trim(), 'new_password': newPassword});
    } catch (e) {
      throw toApiException(e);
    }
  }
}
