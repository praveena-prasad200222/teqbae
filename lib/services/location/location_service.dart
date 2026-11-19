import 'package:geolocator/geolocator.dart';

import '../../constants/app_config.dart';
import '../../models/geo_point.dart';

enum LocationFailure {
  serviceDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  unavailable,
}

class LocationException implements Exception {
  final LocationFailure failure;
  final String message;

  LocationException(this.failure, this.message);

  @override
  String toString() => message;
}

abstract class LocationService {
  Future<GeoPoint> getCurrentPosition();
  Future<bool> isLocationServiceEnabled() async => true;
}

/// Real device GPS with explicit handling of every failure mode in the brief.
class GeolocatorLocationService implements LocationService {
  @override
  Future<bool> isLocationServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<GeoPoint> getCurrentPosition() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationException(
        LocationFailure.serviceDisabled,
        'GPS is turned off. Enable location services and try again.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationException(
        LocationFailure.permissionDenied,
        'Location permission was denied. Allow location access to record attendance.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationException(
        LocationFailure.permissionPermanentlyDenied,
        'Location permission is permanently denied. Open app settings and enable it.',
      );
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      throw LocationException(
        LocationFailure.unavailable,
        'Location permission is unavailable. Please try again.',
      );
    }

    try {
      // 1. Check last known position first for instant response:
      final Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null &&
          DateTime.now().difference(lastKnown.timestamp).inMinutes < 10) {
        return GeoPoint(
          latitude: lastKnown.latitude,
          longitude: lastKnown.longitude,
        );
      }

      // 2. Fast position fix with 4-second timeout using medium accuracy (Wi-Fi/cellular assisted):
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      );
      return GeoPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // 3. Fallback: If getCurrentPosition timed out, use last known position if available:
      final Position? fallback = await Geolocator.getLastKnownPosition();
      if (fallback != null) {
        return GeoPoint(
          latitude: fallback.latitude,
          longitude: fallback.longitude,
        );
      }
      throw LocationException(
        LocationFailure.unavailable,
        'GPS location is unavailable right now. Move outdoors or try again.',
      );
    }
  }
}

/// Deterministic fixed-coordinate source used by the development-only
/// [simulation panel](../../providers/location_simulation_viewmodel.dart) and by
/// unit tests. It is never injected into release builds.
class MockLocationService implements LocationService {
  final double latitude;
  final double longitude;
  final Duration delay;

  MockLocationService({
    double? latitude,
    double? longitude,
    this.delay = Duration.zero,
  })  : latitude = latitude ?? AppConfig.mockLatitude,
        longitude = longitude ?? AppConfig.mockLongitude;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<GeoPoint> getCurrentPosition() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return GeoPoint(latitude: latitude, longitude: longitude);
  }
}
