import '../constants/app_config.dart';

/// Configurable office location used for geofence validation.
class OfficeLocation {
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final int timezoneOffsetMinutes;

  /// False only when the real Teqbae office coordinates were not supplied.
  /// Validation must not report a distance against the 0,0 sentinel.
  final bool isConfigured;

  const OfficeLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.timezoneOffsetMinutes,
    this.isConfigured = true,
  });

  /// Local fallback used before the API has been reached, and when the
  /// cached employee record is not available yet.
  factory OfficeLocation.fallback() => OfficeLocation(
        name: AppConfig.officeName,
        latitude: AppConfig.officeLatitude,
        longitude: AppConfig.officeLongitude,
        radiusMeters: AppConfig.officeRadiusMeters,
        timezoneOffsetMinutes: AppConfig.companyTimezoneOffsetMinutes,
        isConfigured: AppConfig.isOfficeConfigured,
      );

  factory OfficeLocation.fromJson(Map<String, dynamic> json) {
    return OfficeLocation(
      name: (json['name'] as String?) ?? AppConfig.officeName,
      latitude: (json['latitude'] as num?)?.toDouble() ??
          AppConfig.officeLatitude,
      longitude: (json['longitude'] as num?)?.toDouble() ??
          AppConfig.officeLongitude,
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ??
          AppConfig.officeRadiusMeters,
      timezoneOffsetMinutes: (json['timezoneOffsetMinutes'] as num?)?.toInt() ??
          AppConfig.companyTimezoneOffsetMinutes,
      isConfigured: json['isConfigured'] as bool? ??
          (json['latitude'] != null && json['longitude'] != null),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'timezoneOffsetMinutes': timezoneOffsetMinutes,
        'isConfigured': isConfigured,
      };

  @override
  String toString() =>
      'OfficeLocation($name, $latitude, $longitude, ${radiusMeters}m)';
}
