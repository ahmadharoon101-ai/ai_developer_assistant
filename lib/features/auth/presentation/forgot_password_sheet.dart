import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/toast.dart';
import 'auth_controller.dart';

/// Two-step "forgot password": request a code (emailed, or shown directly
/// when the backend has no SMTP configured), then enter it with a new password.
Future<void> showForgotPasswordSheet(BuildContext context, {String? initialEmail}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _ForgotPasswordSheet(initialEmail: initialEmail),
  );
}

class _ForgotPasswordSheet extends ConsumerStatefulWidget {
  const _ForgotPasswordSheet({this.initialEmail});
  final String? initialEmail;

  @override
  ConsumerState<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends ConsumerState<_ForgotPasswordSheet> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _newPassword = TextEditingController();
  final _requestForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  bool _codeRequested = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (!_requestForm.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(authControllerProvider.notifier).forgotPassword(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _codeRequested = true;
        _info = result.devCode != null
            ? '${result.message} ${result.devCode}'
            : result.message;
        if (result.devCode != null) _code.text = result.devCode!;
      });
    } catch (e) {
      if (mounted) setState(() => _error = toApiException(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!_resetForm.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).resetPassword(
          code: _code.text.trim(), newPassword: _newPassword.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, 'Password reset. Sign in with your new password.');
    } catch (e) {
      if (mounted) setState(() => _error = toApiException(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_codeRequested ? 'Enter your reset code' : 'Reset your password',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              _codeRequested
                  ? 'Check your email for an 8-character code, then set a new password.'
                  : 'Enter the email on your account and we will send a reset code.',
              style: TextStyle(color: AppColors.muted),
            ),
            if (_info != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.teal.withOpacity(0.4)),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.teal),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_info!, style: const TextStyle(fontSize: 13))),
                ]),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 16),
            if (!_codeRequested)
              Form(
                key: _requestForm,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: fieldDecoration('Email', icon: Icons.mail_outline),
                    validator: Validators.email,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _requestCode,
                    child: _busy
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Send reset code'),
                  ),
                ]),
              )
            else
              Form(
                key: _resetForm,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextFormField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                    decoration: fieldDecoration('Reset code', icon: Icons.pin_outlined),
                    validator: (v) =>
                        (v == null || v.trim().length < 6) ? 'Enter the code from your email.' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _newPassword,
                    obscureText: true,
                    decoration: fieldDecoration('New password',
                        icon: Icons.lock_outline, hint: 'At least 8 characters, letter + number'),
                    validator: Validators.newPassword,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _reset,
                    child: _busy
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Reset password'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _codeRequested = false),
                    child: const Text('Use a different email'),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      TextEditingValue(text: newValue.text.toUpperCase(), selection: newValue.selection);
}
