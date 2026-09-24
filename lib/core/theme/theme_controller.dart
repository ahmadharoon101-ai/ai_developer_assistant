import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storageKey = 'theme_mode';
const _storage = FlutterSecureStorage();

const _names = {ThemeMode.system: 'system', ThemeMode.light: 'light', ThemeMode.dark: 'dark'};
final _byName = {for (final e in _names.entries) e.value: e.key};

/// The user's chosen theme, persisted across launches. Defaults to dark to
/// match the app's original design; "system" follows the OS setting live.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    Future.microtask(_restore);
    return ThemeMode.dark;
  }

  Future<void> _restore() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      if (saved != null && _byName.containsKey(saved)) state = _byName[saved]!;
    } catch (_) {
      // Best-effort; keep the default if secure storage isn't available.
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await _storage.write(key: _storageKey, value: _names[mode]);
    } catch (_) {
      // Persisting is a nicety; the in-memory switch above already applied.
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
