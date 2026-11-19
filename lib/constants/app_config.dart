/// Compile-time configuration for the REBS HRMS demo app.
///
/// Every value can be overridden with `flutter run/build/test --dart-define=...`
/// so reviewers do not have to edit source code. See README.md for examples.
class AppConfig {
  AppConfig._();

  static const String appName = 'REBS HRMS';

  // ---------------------------------------------------------------------------
  // API
  // ---------------------------------------------------------------------------
  /// Android emulator: 10.0.2.2, iOS simulator: localhost,
  /// physical device: the LAN IP of the machine running the mock server.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8090',
  );

  /// Sent as `X-Mock-Scenario` on every request; the mock API uses it to
  /// produce repeatable success / slow / timeout / error / conflict scenarios.
  static const String mockScenario = String.fromEnvironment(
    'MOCK_SCENARIO',
    defaultValue: 'success',
  );

  /// Short enough that the cached UI is never held hostage by an unreachable
  /// API, long enough for the local mock server and normal mobile latency.
  static const Duration apiTimeout = Duration(seconds: 8);

  // ---------------------------------------------------------------------------
  // Office / geofence
  // ---------------------------------------------------------------------------
  /// Teqbae is the company; REBS is only the machine-test/project name.
  /// Coordinates are deliberately NOT bundled: supply the real Teqbae, Kochi
  /// latitude/longitude at build/run time with OFFICE_LAT / OFFICE_LNG.
  static const String officeName = String.fromEnvironment(
    'OFFICE_NAME',
    defaultValue: 'Teqbae, Kochi',
  );

  static String? get _officeLatitudeText {
    const String value = String.fromEnvironment('OFFICE_LAT');
    return value.isEmpty ? null : value;
  }

  static String? get _officeLongitudeText {
    const String value = String.fromEnvironment('OFFICE_LNG');
    return value.isEmpty ? null : value;
  }

  static double? get configuredOfficeLatitude =>
      double.tryParse(_officeLatitudeText ?? '');
  static double? get configuredOfficeLongitude =>
      double.tryParse(_officeLongitudeText ?? '');

  static bool get isOfficeConfigured =>
      configuredOfficeLatitude != null && configuredOfficeLongitude != null;

  /// Sentinel values are used only when no real coordinates were supplied.
  /// [OfficeLocation.isConfigured] carries this flag so validation can show a
  /// configuration message instead of pretending these are Teqbae's coords.
  static double get officeLatitude => configuredOfficeLatitude ?? 0.0;
  static double get officeLongitude => configuredOfficeLongitude ?? 0.0;

  static final double officeRadiusMeters = double.parse(
    const String.fromEnvironment('OFFICE_RADIUS_M', defaultValue: '200'),
  );

  static String get officeConfigurationHint =>
      'Set the real Teqbae, Kochi office coordinates with '
      '--dart-define=OFFICE_LAT=<latitude> '
      '--dart-define=OFFICE_LNG=<longitude>.';

  // ---------------------------------------------------------------------------
  // Company timezone (fixed offset from UTC, in minutes; 330 = UTC+05:30).
  // A fixed offset is intentional: it keeps "the company day" deterministic
  // without shipping a timezone database. See README.md for the rationale.
  // ---------------------------------------------------------------------------
  static const int companyTimezoneOffsetMinutes = int.fromEnvironment(
    'COMPANY_TZ_OFFSET_MINUTES',
    defaultValue: 330,
  );
  static const String companyTimezoneLabel = String.fromEnvironment(
    'COMPANY_TZ_LABEL',
    defaultValue: 'IST (UTC+05:30)',
  );

  // ---------------------------------------------------------------------------
  // GPS simulation (DEVELOPMENT / PROFILE builds only)
  // ---------------------------------------------------------------------------
  /// The simulation panel pre-fills from the single central office config.
  /// There are no separate MOCK_LAT / MOCK_LNG coordinates any more.
  static double get mockLatitude => officeLatitude;
  static double get mockLongitude => officeLongitude;

  // Login is out of scope; one preconfigured employee is used.
  static const String employeeId = 'EMP-1001';

  // Hive box names.
  static const String eventsBox = 'attendance_events';
  static const String cacheBox = 'app_cache';
}
