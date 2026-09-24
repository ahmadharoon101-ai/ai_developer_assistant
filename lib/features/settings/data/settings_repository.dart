import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';

class AppSettings {
  const AppSettings({
    required this.responseStyle,
    required this.temperature,
    required this.model,
    required this.historyMessages,
    required this.provider,
    required this.defaultModel,
    required this.availableModels,
  });
  final String responseStyle;
  final double temperature;
  final String model;
  final int historyMessages;
  final String provider;
  final String defaultModel;
  final List<String> availableModels;

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        responseStyle: j['response_style'] as String,
        temperature: (j['temperature'] as num).toDouble(),
        model: (j['model'] as String?) ?? '',
        historyMessages: (j['history_messages'] as num).toInt(),
        provider: j['provider'] as String,
        defaultModel: j['default_model'] as String,
        availableModels: [for (final m in j['available_models'] as List) m as String],
      );
}

class SettingsRepository {
  SettingsRepository(this._dio);
  final Dio _dio;

  Future<AppSettings> load() async {
    try {
      final res = await _dio.get<dynamic>(ApiConstants.settings);
      return AppSettings.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw toApiException(e);
    }
  }

  Future<AppSettings> save(AppSettings s) async {
    try {
      final res = await _dio.put<dynamic>(ApiConstants.settings, data: {
        'response_style': s.responseStyle,
        'temperature': s.temperature,
        'model': s.model,
        'history_messages': s.historyMessages,
      });
      return AppSettings.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw toApiException(e);
    }
  }
}

final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => SettingsRepository(ref.read(dioProvider)));

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsController, AppSettings>(AppSettingsController.new);

class AppSettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.read(settingsRepositoryProvider).load();

  Future<void> save(AppSettings next) async {
    state = const AsyncLoading<AppSettings>().copyWithPrevious(state);
    state = await AsyncValue.guard(() => ref.read(settingsRepositoryProvider).save(next));
  }
}
