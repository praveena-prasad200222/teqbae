import 'dart:math';

import '../models/geo_point.dart';
import '../models/office_location.dart';

/// Haversine great-circle distance calculation.
class GeoFence {
  GeoFence._();

  static const double earthRadiusMeters = 6371000;

  static double distanceMeters(GeoPoint from, GeoPoint to) {
    final double lat1 = _radians(from.latitude);
    final double lat2 = _radians(to.latitude);
    final double deltaLat = lat2 - lat1;
    final double deltaLng = _radians(to.longitude - from.longitude);

    final double a = pow(sin(deltaLat / 2), 2) +
        cos(lat1) * cos(lat2) * pow(sin(deltaLng / 2), 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static bool isWithin({
    required GeoPoint current,
    required OfficeLocation office,
  }) {
    // A 0,0 sentinel from missing OFFICE_LAT/OFFICE_LNG must never count as
    // "inside". AttendanceRules also blocks it with a configuration message.
    if (!office.isConfigured) return false;
    final GeoPoint origin = GeoPoint(
      latitude: office.latitude,
      longitude: office.longitude,
    );
    return distanceMeters(origin, current) <= office.radiusMeters;
  }

  static double _radians(double degrees) => degrees * pi / 180;
}
