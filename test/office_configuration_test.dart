import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teqbae/constants/app_config.dart';
import 'package:teqbae/models/geo_point.dart';
import 'package:teqbae/models/office_location.dart';
import 'package:teqbae/utils/geofence.dart';

// Built from fragments so this guard test does not itself contain the stale
// literals it is looking for.
const List<String> _staleTokens = <String>[
  'REBS H' 'Q',
  'H' 'yderabad',
  '17.3850' '44',
  '78.4866' '71',
  '904' '418',
];

Iterable<File> _scannedFiles() sync* {
  for (final String directoryName in <String>[
    'lib',
    'test',
    'mock_api',
  ]) {
    final Directory directory = Directory(directoryName);
    if (!directory.existsSync()) continue;
    for (final FileSystemEntity entity
        in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String normalized = entity.path.replaceAll(r'\', '/');
      if (normalized.endsWith('/office_configuration_test.dart')) continue;
      yield entity;
    }
  }

  for (final String fileName in <String>[
    'README.md',
    'pubspec.yaml',
    'analysis_options.yaml',
  ]) {
    final File file = File(fileName);
    if (file.existsSync()) yield file;
  }
}

void main() {
  group('Office configuration', () {
    test('stale office name and old coordinates are absent', () {
      final List<String> offenders = <String>[];

      for (final File file in _scannedFiles()) {
        final String contents = file.readAsStringSync();
        for (final String token in _staleTokens) {
          if (contents.contains(token)) {
            offenders.add('${file.path} contains "$token"');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Remove every stale office reference:\n${offenders.join('\n')}',
      );
    });

    test('central config is Teqbae, Kochi with the unchanged 200 m geofence',
        () {
      expect(AppConfig.officeName.toLowerCase(), contains('teqbae'));
      expect(AppConfig.officeName.toLowerCase(), contains('kochi'));
      expect(AppConfig.officeRadiusMeters, 200);

      final OfficeLocation office = OfficeLocation.fallback();
      expect(office.name, AppConfig.officeName);
      expect(office.latitude, AppConfig.officeLatitude);
      expect(office.longitude, AppConfig.officeLongitude);
      expect(office.radiusMeters, AppConfig.officeRadiusMeters);
      expect(office.isConfigured, AppConfig.isOfficeConfigured);
    });

    test('configured office coordinates drive distance and geofence checks',
        () {
      const OfficeLocation office = OfficeLocation(
        name: 'Configured Test Office',
        latitude: 10.0,
        longitude: 76.0,
        radiusMeters: 200,
        timezoneOffsetMinutes: 330,
      );
      const GeoPoint inside =
          GeoPoint(latitude: 10.000900, longitude: 76.0);
      const GeoPoint outside =
          GeoPoint(latitude: 10.002000, longitude: 76.0);

      const GeoPoint origin = GeoPoint(latitude: 10.0, longitude: 76.0);
      final double distance = GeoFence.distanceMeters(origin, inside);
      expect(distance, greaterThan(90));
      expect(distance, lessThan(110));
      expect(GeoFence.isWithin(current: inside, office: office), isTrue);
      expect(GeoFence.isWithin(current: outside, office: office), isFalse);
    });

    test('unconfigured office is never inside the geofence', () {
      const OfficeLocation unconfigured = OfficeLocation(
        name: 'Teqbae, Kochi',
        latitude: 0,
        longitude: 0,
        radiusMeters: 200,
        timezoneOffsetMinutes: 330,
        isConfigured: false,
      );
      const GeoPoint origin = GeoPoint(latitude: 0, longitude: 0);

      expect(unconfigured.isConfigured, isFalse);
      expect(GeoFence.isWithin(current: origin, office: unconfigured), isFalse);
    });

    test('JSON round-trip preserves the configured flag', () {
      final OfficeLocation restored = OfficeLocation.fromJson(
        <String, dynamic>{
          'name': 'Teqbae, Kochi',
          'latitude': 10.0,
          'longitude': 76.0,
          'radiusMeters': 200,
          'timezoneOffsetMinutes': 330,
          'isConfigured': false,
        },
      );

      expect(restored.isConfigured, isFalse);
      expect(restored.toJson()['isConfigured'], isFalse);
    });
  });
}
