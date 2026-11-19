import 'package:flutter_test/flutter_test.dart';
import 'package:teqbae/constants/app_config.dart';
import 'package:teqbae/providers/api_settings_viewmodel.dart';

import 'helpers/fake_api_client.dart';
import 'helpers/in_memory_local_storage.dart';

void main() {
  late InMemoryLocalStorage storage;
  late FakeApiClient api;
  late ApiSettingsViewModel vm;

  setUp(() {
    storage = InMemoryLocalStorage();
    api = FakeApiClient();
    vm = ApiSettingsViewModel(storage: storage, apiClient: api);
  });

  test('saved override is applied to the shared API client on init', () async {
    storage.apiBaseUrl = 'http://192.168.1.50:8090/';

    await vm.init();

    expect(vm.baseUrl, 'http://192.168.1.50:8090');
    expect(api.baseUrl, 'http://192.168.1.50:8090');
  });

  test('invalid base URL is rejected without changing requests', () async {
    final result = await vm.saveBaseUrl('192.168.1.50:8090');

    expect(result.success, isFalse);
    expect(result.message, contains('full URL'));
    expect(api.baseUrl, 'http://localhost');
    expect(storage.apiBaseUrl, isNull);
  });

  test('valid base URL is persisted and used immediately', () async {
    int notifications = 0;
    vm.addListener(() => notifications++);

    final result = await vm.saveBaseUrl('http://192.168.1.10:8090///');

    expect(result.success, isTrue);
    expect(vm.baseUrl, 'http://192.168.1.10:8090');
    expect(api.baseUrl, 'http://192.168.1.10:8090');
    expect(storage.apiBaseUrl, 'http://192.168.1.10:8090');
    expect(notifications, greaterThan(0));
  });

  test('reset restores the compile-time default', () async {
    await vm.saveBaseUrl('http://192.168.1.10:8090');

    final result = await vm.resetToDefault();

    expect(result.success, isTrue);
    expect(vm.baseUrl, AppConfig.apiBaseUrl);
    expect(api.baseUrl, AppConfig.apiBaseUrl);
    expect(storage.apiBaseUrl, AppConfig.apiBaseUrl);
  });
}
