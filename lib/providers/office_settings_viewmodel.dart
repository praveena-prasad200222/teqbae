import 'package:flutter/foundation.dart';

import '../constants/app_config.dart';
import '../models/action_result.dart';
import '../models/office_location.dart';
import '../services/storage/local_storage.dart';

/// Runtime office coordinates for reviewers who cannot rebuild with defines.
///
/// Nothing is bundled in the source: the coordinates are entered on the device
/// and stored locally. The 200 m rule is unchanged; this only supplies the
/// reference point that the rule is measured from.
class OfficeSettingsViewModel extends ChangeNotifier {
  OfficeSettingsViewModel({required this.storage});

  final LocalStorage storage;

  double? _latitude;
  double? _longitude;
  bool _isGeneratedTestPoint = false;

  bool get isConfigured => _latitude != null && _longitude != null;
  bool get isGeneratedTestPoint => _isGeneratedTestPoint;
  double? get latitude => _latitude;
  double? get longitude => _longitude;

  OfficeLocation get office {
    if (_latitude != null && _longitude != null) {
      return OfficeLocation(
        name: _isGeneratedTestPoint
            ? 'DEBUG generated test point (not Teqbae)'
            : '${AppConfig.officeName} (device test coordinates)',
        latitude: _latitude!,
        longitude: _longitude!,
        radiusMeters: AppConfig.officeRadiusMeters,
        timezoneOffsetMinutes: AppConfig.companyTimezoneOffsetMinutes,
        isConfigured: true,
      );
    }
    return OfficeLocation.fallback();
  }

  Future<void> init() async {
    final ({double latitude, double longitude})? saved =
        await storage.getOfficeCoordinates();
    if (saved != null) {
      _latitude = saved.latitude;
      _longitude = saved.longitude;
      notifyListeners();
      return;
    }

    // DEBUG-only convenience: when no real coordinates were supplied, create a
    // local test reference so the reviewer can exercise the unchanged 200 m
    // rule immediately. No coordinate is bundled and RELEASE never does this.
    if (!kReleaseMode && !AppConfig.isOfficeConfigured) {
      await useGeneratedTestPoint();
    }
  }

  Future<void> useGeneratedTestPoint() async {
    final int seed = DateTime.now().microsecondsSinceEpoch;
    final double latitude = ((seed % 10000000) / 100000.0) - 50;
    final double longitude = (((seed ~/ 10000000) % 10000000) / 100000.0) - 100;
    await saveCoordinates(latitude.toStringAsFixed(6), longitude.toStringAsFixed(6));
    _isGeneratedTestPoint = true;
    notifyListeners();
  }

  Future<ActionResult> saveCoordinates(String latitudeText, String longitudeText) async {
    final double? latitude = double.tryParse(latitudeText.trim());
    final double? longitude = double.tryParse(longitudeText.trim());
    if (latitude == null || latitude < -90 || latitude > 90) {
      return ActionResult.fail('Latitude must be between -90 and 90.');
    }
    if (longitude == null || longitude < -180 || longitude > 180) {
      return ActionResult.fail('Longitude must be between -180 and 180.');
    }
    try {
      await storage.setOfficeCoordinates(latitude, longitude);
      _latitude = latitude;
      _longitude = longitude;
      _isGeneratedTestPoint = false;
      notifyListeners();
      return ActionResult.ok(
        'Test office coordinates saved. Inside 200 m / Outside 200 m are ready.',
      );
    } catch (error) {
      return ActionResult.fail('Could not save office coordinates: $error');
    }
  }
}
