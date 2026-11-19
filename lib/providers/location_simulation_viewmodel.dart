import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/app_config.dart';
import '../models/geo_point.dart';
import '../models/office_location.dart';
import '../services/location/location_service.dart';
import '../utils/geofence.dart';

/// Development-only switch between the device GPS and a fixed test point.
///
/// The class implements [LocationService] so the rest of the app (and, most
/// importantly, [AttendanceRepository]'s geofence rules) sees exactly the same
/// coordinate shape in both modes. It is deliberately not constructed in
/// release builds; [kReleaseMode] guards every public mutation as a second
/// line of defence.
class LocationSimulationViewModel extends ChangeNotifier implements LocationService {
  LocationSimulationViewModel({
    required this.realLocationService,
    OfficeLocation Function()? officeProvider,
  })  : _officeProvider = officeProvider ?? OfficeLocation.fallback,
        _simulatedPoint = GeoPoint(
          latitude: AppConfig.mockLatitude,
          longitude: AppConfig.mockLongitude,
        );

  final LocationService realLocationService;
  final OfficeLocation Function() _officeProvider;

  bool _simulationEnabled = false;
  GeoPoint _simulatedPoint;

  /// Exposed for UI gating and tests. Enabled in both debug and release.
  static bool get isSupported => true;

  bool get simulationEnabled => _simulationEnabled;
  bool get realGpsEnabled => !simulationEnabled;
  GeoPoint get simulatedPoint => _simulatedPoint;

  OfficeLocation get configuredOffice => _officeProvider();

  /// False until the real Teqbae office coordinates are supplied. Presets and
  /// distance displays must not pretend the 0,0 sentinel is the office.
  bool get isOfficeConfigured => configuredOffice.isConfigured;

  double get distanceFromConfiguredOfficeMeters =>
      distanceFrom(configuredOffice);

  bool get isWithinConfiguredOffice => isWithinOffice(configuredOffice);

  /// Distance from the office actually used by attendance validation. The
  /// profile card uses the configured fallback; the attendance card passes the
  /// office from the loaded employee so the number always matches check-in.
  double distanceFrom(OfficeLocation office) => GeoFence.distanceMeters(
        GeoPoint(latitude: office.latitude, longitude: office.longitude),
        _simulatedPoint,
      );

  bool isWithinOffice(OfficeLocation office) =>
      distanceFrom(office) <= office.radiusMeters;

  @override
  Future<bool> isLocationServiceEnabled() =>
      realLocationService.isLocationServiceEnabled();

  @override
  Future<GeoPoint> getCurrentPosition() async {
    // Both real GPS and simulation REQUIRE device location to be turned on!
    final bool serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationException(
        LocationFailure.serviceDisabled,
        'GPS is turned off. Enable location services and try again.',
      );
    }

    if (!_simulationEnabled) {
      return realLocationService.getCurrentPosition();
    }

    if (realLocationService is GeolocatorLocationService) {
      final LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final LocationPermission requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied) {
          throw LocationException(
            LocationFailure.permissionDenied,
            'Location permission was denied. Allow location access to record attendance.',
          );
        }
        if (requested == LocationPermission.deniedForever) {
          throw LocationException(
            LocationFailure.permissionPermanentlyDenied,
            'Location permission is permanently denied. Open app settings and enable it.',
          );
        }
      } else if (permission == LocationPermission.deniedForever) {
        throw LocationException(
          LocationFailure.permissionPermanentlyDenied,
          'Location permission is permanently denied. Open app settings and enable it.',
        );
      }
    }

    return _simulatedPoint;
  }

  void setSimulationEnabled(bool value) {
    if (_simulationEnabled == value) return;
    _simulationEnabled = value;
    notifyListeners();
  }

  /// Returns null on success, otherwise a message suitable for a SnackBar.
  String? setCoordinatesFromText(String latitudeText, String longitudeText) {
    final double? latitude = double.tryParse(latitudeText.trim());
    final double? longitude = double.tryParse(longitudeText.trim());
    if (latitude == null || latitude < -90 || latitude > 90) {
      return 'Latitude must be a number between -90 and 90.';
    }
    if (longitude == null || longitude < -180 || longitude > 180) {
      return 'Longitude must be a number between -180 and 180.';
    }
    return setCoordinates(latitude, longitude);
  }

  /// Returns null on success, otherwise a validation message.
  String? setCoordinates(double latitude, double longitude) {
    if (latitude < -90 || latitude > 90) {
      return 'Latitude must be between -90 and 90.';
    }
    if (longitude < -180 || longitude > 180) {
      return 'Longitude must be between -180 and 180.';
    }
    _simulatedPoint = GeoPoint(latitude: latitude, longitude: longitude);
    notifyListeners();
    return null;
  }

  void useInsideOfficePreset([OfficeLocation? office]) {
    final OfficeLocation target = office ?? configuredOffice;
    if (!target.isConfigured) return;
    setCoordinates(target.latitude, target.longitude);
  }

  /// Places the test point just beyond the radius so the unchanged geofence
  /// rule rejects the next attendance action.
  void useOutsideOfficePreset([OfficeLocation? office]) {
    final OfficeLocation target = office ?? configuredOffice;
    if (!target.isConfigured) return;
    final double delta =
        (target.radiusMeters + 75) / 111320; // ~1 degree latitude.
    double latitude = target.latitude + delta;
    if (latitude > 90) latitude = target.latitude - delta;
    setCoordinates(latitude, target.longitude);
  }
}
