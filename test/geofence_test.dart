import 'package:flutter_test/flutter_test.dart';

import 'package:teqbae/models/geo_point.dart';
import 'package:teqbae/models/office_location.dart';
import 'package:teqbae/utils/geofence.dart';

void main() {
  const GeoPoint officePoint = GeoPoint(latitude: 10.000000, longitude: 76.000000);
  final OfficeLocation office = OfficeLocation(
    name: 'Office',
    latitude: officePoint.latitude,
    longitude: officePoint.longitude,
    radiusMeters: 200,
    timezoneOffsetMinutes: 330,
  );

  test('distance for ~100 metres north is close to 100 m', () {
    // 0.0009 degrees of latitude is roughly 100 metres.
    const GeoPoint near = GeoPoint(latitude: 10.000900, longitude: 76.000000);
    final double distance = GeoFence.distanceMeters(officePoint, near);
    expect(distance, greaterThan(90));
    expect(distance, lessThan(110));
  });

  test('points inside and outside a 200 m geofence are classified correctly', () {
    const GeoPoint inside = GeoPoint(latitude: 10.001000, longitude: 76.000000);
    const GeoPoint outside = GeoPoint(latitude: 10.002000, longitude: 76.000000);

    expect(GeoFence.isWithin(current: inside, office: office), isTrue);
    expect(GeoFence.isWithin(current: outside, office: office), isFalse);
  });

  test('distance is symmetric and zero for identical points', () {
    expect(GeoFence.distanceMeters(officePoint, officePoint), closeTo(0, 0.01));
    const GeoPoint other = GeoPoint(latitude: 17.39, longitude: 78.49);
    expect(
      GeoFence.distanceMeters(officePoint, other),
      closeTo(GeoFence.distanceMeters(other, officePoint), 0.01),
    );
  });
}
