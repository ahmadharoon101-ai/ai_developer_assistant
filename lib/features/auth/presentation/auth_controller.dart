import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/storage/token_storage.dart';
import '../data/auth_repository_impl.dart';
import '../domain/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
    (ref) => RemoteAuthRepository(ref.read(dioProvider), ref.read(tokenStorageProvider)));

/// AsyncLoading only while the stored session is being restored (splash).
/// signIn / register throw ApiException so pages can show errors inline.
class AuthController extends AsyncNotifier<AuthUser?> {
  @override
  Future<AuthUser?> build() async {
    // Let the network layer sign us out when the server says the session is invalid.
    Future.microtask(
        () => ref.read(sessionExpiredProvider.notifier).state = () => _expire());
    final repo = ref.read(authRepositoryProvider);
    final results = await Future.wait<Object?>([
      repo.restoreSession(),
      Future<void>.delayed(const Duration(milliseconds: 1800)), // splash
    ]);
    return results.first as AuthUser?;
  }

  Future<void> _expire() async {
    if (state.valueOrNull == null) return;
    await ref.read(authRepositoryProvider).clearLocalSession();
    state = const AsyncData(null);
  }

  Future<void> signIn(String email, String password) async {
    final user =
        await ref.read(authRepositoryProvider).login(email: email, password: password);
    state = AsyncData(user);
  }

  /// Creates the account. Does not sign in — the caller should navigate to
  /// the login screen once this resolves.
  Future<void> register(String name, String email, String password) =>
      ref.read(authRepositoryProvider).register(name: name, email: email, password: password);

  Future<void> updateProfile(String name) async {
    final user = await ref.read(authRepositoryProvider).updateProfile(name);
    state = AsyncData(user);
  }

  Future<void> changePassword(String current, String next) =>
      ref.read(authRepositoryProvider).changePassword(current, next);

  Future<ForgotPasswordResult> forgotPassword(String email) =>
      ref.read(authRepositoryProvider).forgotPassword(email);

  Future<void> resetPassword({required String code, required String newPassword}) =>
      ref.read(authRepositoryProvider).resetPassword(code: code, newPassword: newPassword);

  Future<void> signOutEverywhere() async {
    await ref.read(authRepositoryProvider).logoutEverywhere();
    await signOut();
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthUser?>(AuthController.new);
