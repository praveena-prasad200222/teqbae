import 'package:flutter_test/flutter_test.dart';
import 'package:teqbae/di.dart';
import 'package:teqbae/models/geo_point.dart';
import 'package:teqbae/models/office_location.dart';
import 'package:teqbae/providers/location_simulation_viewmodel.dart';

import 'helpers/fake_location_service.dart';

OfficeLocation _office({bool configured = true}) => OfficeLocation(
      name: 'Test Office',
      latitude: 10.0,
      longitude: 76.0,
      radiusMeters: 200,
      timezoneOffsetMinutes: 330,
      isConfigured: configured,
    );

void main() {
  const GeoPoint officePoint = GeoPoint(latitude: 10.0, longitude: 76.0);
  const GeoPoint realPoint = GeoPoint(latitude: 10.05, longitude: 76.05);

  group('Location simulation ViewModel', () {
    test('real GPS is active by default', () async {
      final FakeLocationService real =
          FakeLocationService(point: realPoint);
      final LocationSimulationViewModel vm =
          LocationSimulationViewModel(realLocationService: real);

      expect(vm.realGpsEnabled, isTrue);
      expect(vm.simulationEnabled, isFalse);
      expect(await vm.getCurrentPosition(), same(realPoint));
    });

    test('simulated coordinates flow through the same LocationService', () async {
      final FakeLocationService real =
          FakeLocationService(point: realPoint);
      final LocationSimulationViewModel vm =
          LocationSimulationViewModel(realLocationService: real);
      final OfficeLocation office = _office();

      vm.setSimulationEnabled(true);
      final String? error =
          vm.setCoordinatesFromText('10.000900', '76.000000');

      expect(error, isNull);
      expect(vm.simulationEnabled, isTrue);
      expect(vm.isWithinOffice(office), isTrue);
      expect(vm.distanceFrom(office), greaterThan(90));
      expect(vm.distanceFrom(office), lessThan(110));

      final GeoPoint position = await vm.getCurrentPosition();
      expect(position.latitude, 10.000900);
      expect(position.longitude, 76.000000);
    });

    test('outside preset produces a point beyond the unchanged 200 m geofence',
        () {
      final OfficeLocation office = _office();
      final LocationSimulationViewModel vm = LocationSimulationViewModel(
        realLocationService: FakeLocationService(point: realPoint),
      );

      vm.useInsideOfficePreset(office);
      expect(vm.isWithinOffice(office), isTrue);
      expect(vm.simulatedPoint.latitude, officePoint.latitude);
      expect(vm.simulatedPoint.longitude, officePoint.longitude);

      vm.useOutsideOfficePreset(office);
      expect(vm.isWithinOffice(office), isFalse);
      expect(vm.distanceFrom(office), greaterThan(200));
    });

    test('presets do nothing when office coordinates are not configured', () {
      final LocationSimulationViewModel vm = LocationSimulationViewModel(
        realLocationService: FakeLocationService(point: realPoint),
      );
      final GeoPoint original = vm.simulatedPoint;
      final OfficeLocation unconfigured = _office(configured: false);

      vm.useInsideOfficePreset(unconfigured);
      vm.useOutsideOfficePreset(unconfigured);

      expect(vm.simulatedPoint.latitude, original.latitude);
      expect(vm.simulatedPoint.longitude, original.longitude);
    });

    test('invalid coordinates are rejected without changing the point', () {
      final LocationSimulationViewModel vm = LocationSimulationViewModel(
        realLocationService: FakeLocationService(point: realPoint),
      );
      final GeoPoint original = vm.simulatedPoint;

      expect(vm.setCoordinatesFromText('abc', '76.48'), contains('Latitude'));
      expect(vm.setCoordinatesFromText('10.2', '200'), contains('Longitude'));
      expect(vm.simulatedPoint.latitude, original.latitude);
      expect(vm.simulatedPoint.longitude, original.longitude);
    });

    test('release wiring never creates the simulation controller', () {
      final FakeLocationService real =
          FakeLocationService(point: realPoint);

      final LocationServices release = AppDependencies.createLocationServices(
        isReleaseMode: true,
        realService: real,
      );
      expect(release.location, same(real));
      expect(release.simulation, isNull);

      final LocationServices debug = AppDependencies.createLocationServices(
        isReleaseMode: false,
        realService: real,
      );
      expect(debug.simulation, isNotNull);
      expect(debug.location, same(debug.simulation));
      expect(debug.simulation!.realGpsEnabled, isTrue);

      final LocationServices releaseEnabled = AppDependencies.createLocationServices(
        isReleaseMode: true,
        realService: real,
        enableSimulationInRelease: true,
      );
      expect(releaseEnabled.simulation, isNotNull);
      expect(releaseEnabled.location, same(releaseEnabled.simulation));
    });
  });
}
