class AuthUser {
  const AuthUser({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'].toString(),
        name: j['name'] as String,
        email: j['email'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};

  AuthUser copyWith({String? name}) =>
      AuthUser(id: id, name: name ?? this.name, email: email);
}

/// Result of requesting a password-reset code. If the server has no SMTP
/// configured it hands the code back directly (`devCode`) instead of emailing
/// it, so the flow stays testable without mail infrastructure.
class ForgotPasswordResult {
  const ForgotPasswordResult({required this.message, this.devCode});
  final String message;
  final String? devCode;
}

abstract class AuthRepository {
  Future<AuthUser?> restoreSession();
  Future<AuthUser> login({required String email, required String password});

  /// Creates the account but does NOT sign in — the caller is expected to
  /// send the person to the login screen afterward.
  Future<void> register({required String name, required String email, required String password});

  Future<AuthUser> updateProfile(String name);
  Future<void> changePassword(String current, String next);
  Future<void> logoutEverywhere();
  Future<void> logout();
  Future<void> clearLocalSession();

  Future<ForgotPasswordResult> forgotPassword(String email);
  Future<void> resetPassword({required String code, required String newPassword});
}
