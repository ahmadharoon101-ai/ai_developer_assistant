class Validators {
  const Validators._();

  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? name(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Enter your full name.';
    if (t.length < 2) return 'Name must be at least 2 characters.';
    return null;
  }

  static String? email(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Enter your email address.';
    if (!_email.hasMatch(t)) return 'Enter a valid email, like you@company.com.';
    return null;
  }

  static String? loginPassword(String? v) =>
      (v == null || v.isEmpty) ? 'Enter your password.' : null;

  static String? newPassword(String? v) {
    if (v == null || v.isEmpty) return 'Create a password.';
    if (v.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Include at least one letter and one number.';
    }
    return null;
  }

  static String? Function(String?) confirm(String Function() original) =>
      (v) => (v == null || v.isEmpty)
          ? 'Confirm your password.'
          : (v != original() ? 'Passwords do not match.' : null);
}
