import 'package:flutter_test/flutter_test.dart';
import 'package:teqbae/providers/office_settings_viewmodel.dart';

import 'helpers/in_memory_local_storage.dart';

void main() {
  late InMemoryLocalStorage storage;
  late OfficeSettingsViewModel vm;

  setUp(() {
    storage = InMemoryLocalStorage();
    vm = OfficeSettingsViewModel(storage: storage);
  });

  test('DEBUG generates a local test point when no coordinates are supplied',
      () async {
    await vm.init();

    expect(vm.isConfigured, isTrue);
    expect(vm.isGeneratedTestPoint, isTrue);
    expect(storage.officeCoordinates, isNotNull);
    expect(vm.office.radiusMeters, 200);
  });

  test('saved device coordinates are restored on init', () async {
    storage.officeCoordinates = (latitude: 9.9312, longitude: 76.2673);

    await vm.init();

    expect(vm.isConfigured, isTrue);
    expect(vm.office.latitude, 9.9312);
    expect(vm.office.longitude, 76.2673);
    expect(vm.office.isConfigured, isTrue);
    expect(vm.office.radiusMeters, 200);
  });

  test('valid coordinates are saved and enable the geofence reference', () async {
    final result = await vm.saveCoordinates('9.9312', '76.2673');

    expect(result.success, isTrue);
    expect(vm.office.isConfigured, isTrue);
    expect(storage.officeCoordinates?.latitude, 9.9312);
    expect(storage.officeCoordinates?.longitude, 76.2673);
  });

  test('invalid coordinates are rejected', () async {
    final result = await vm.saveCoordinates('91', '76');

    expect(result.success, isFalse);
    expect(result.message, contains('Latitude'));
    expect(vm.isConfigured, isFalse);
    expect(storage.officeCoordinates, isNull);
  });
}
