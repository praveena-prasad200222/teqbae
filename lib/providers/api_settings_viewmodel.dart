import 'package:flutter/foundation.dart';

import '../constants/app_config.dart';
import '../models/action_result.dart';
import '../services/api/api_client.dart';
import '../services/storage/local_storage.dart';

/// Owns the runtime API base URL override.
///
/// The compile-time value in AppConfig remains the default. A reviewer testing
/// on a physical phone can save the computer's LAN IP from Profile, and every
/// request (dashboard, leave, attendance and sync) uses it immediately.
class ApiSettingsViewModel extends ChangeNotifier {
  ApiSettingsViewModel({
    required this.storage,
    required this.apiClient,
    String? initialBaseUrl,
  }) : _baseUrl = ApiClient.normalizeBaseUrl(
          initialBaseUrl ?? AppConfig.apiBaseUrl,
        );

  final LocalStorage storage;
  final ApiClient apiClient;

  String _baseUrl;
  bool _isSaving = false;

  String get baseUrl => _baseUrl;
  bool get isSaving => _isSaving;

  /// Applies a previously saved override, if any, during app startup.
  Future<void> init() async {
    final String? saved = await storage.getApiBaseUrl();
    if (saved == null || saved.trim().isEmpty) return;
    if (ApiClient.validateBaseUrl(saved) != null) return;

    const String emulatorOnly = 'http://10.0.2.2:8090';
    final String compiledDefault =
        ApiClient.normalizeBaseUrl(AppConfig.apiBaseUrl);
    // A stale emulator-only override makes every request fail on a physical
    // phone. When this build targets another host, migrate that setting once.
    if (ApiClient.normalizeBaseUrl(saved) == emulatorOnly &&
        compiledDefault != emulatorOnly) {
      await storage.setApiBaseUrl(compiledDefault);
      _apply(compiledDefault);
      return;
    }
    _apply(saved);
  }

  Future<ActionResult> saveBaseUrl(String value) async {
    final String? error = ApiClient.validateBaseUrl(value);
    if (error != null) return ActionResult.fail(error);

    final String normalized = ApiClient.normalizeBaseUrl(value);
    _isSaving = true;
    notifyListeners();
    try {
      await storage.setApiBaseUrl(normalized);
      _apply(normalized);
      return ActionResult.ok(
        'API base URL saved as $normalized. Retrying the dashboard and pending sync.',
      );
    } catch (error) {
      return ActionResult.fail('Could not save the API base URL: $error');
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<ActionResult> resetToDefault() =>
      saveBaseUrl(AppConfig.apiBaseUrl);

  void _apply(String value) {
    final String normalized = ApiClient.normalizeBaseUrl(value);
    _baseUrl = normalized;
    apiClient.setBaseUrl(normalized);
    notifyListeners();
  }
}
