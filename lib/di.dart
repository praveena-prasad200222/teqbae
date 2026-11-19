import 'package:flutter/foundation.dart';

import 'services/api/api_client.dart';
import 'services/location/location_service.dart';
import 'services/network/connectivity_service.dart';
import 'services/storage/hive_local_storage.dart';
import 'services/storage/local_storage.dart';
import 'services/sync/sync_engine.dart';
import 'models/office_location.dart';
import 'repositories/attendance_repository.dart';
import 'repositories/employee_repository.dart';
import 'repositories/leave_repository.dart';
import 'providers/api_settings_viewmodel.dart';
import 'providers/attendance_viewmodel.dart';
import 'providers/connectivity_viewmodel.dart';
import 'providers/dashboard_viewmodel.dart';
import 'providers/leave_viewmodel.dart';
import 'providers/location_simulation_viewmodel.dart';
import 'providers/office_settings_viewmodel.dart';
import 'providers/sync_viewmodel.dart';
import 'utils/company_clock.dart';

/// Split out so release-mode wiring can be unit tested without Flutter bindings.
class LocationServices {
  const LocationServices({
    required this.location,
    required this.simulation,
  });

  final LocationService location;
  final LocationSimulationViewModel? simulation;
}

/// Manual dependency injection. A DI package would be overkill for this app.
class AppDependencies {
  final CompanyClock clock;
  final LocalStorage storage;
  final ApiClient apiClient;
  final ApiSettingsViewModel apiSettings;
  final OfficeSettingsViewModel officeSettings;
  final EmployeeRepository employeeRepository;
  final AttendanceRepository attendanceRepository;
  final LeaveRepository leaveRepository;
  final LocationService locationService;

  /// Null in release builds. The Provider is omitted there as well, so the
  /// simulation UI cannot be reached by a reviewer or by an end user.
  final LocationSimulationViewModel? locationSimulation;
  final ConnectivityService connectivityService;
  final SyncEngine syncEngine;
  final ConnectivityViewModel connectivity;
  final SyncViewModel sync;
  final DashboardViewModel dashboard;
  final AttendanceViewModel attendance;
  final LeaveViewModel leave;

  AppDependencies({
    required this.clock,
    required this.storage,
    required this.apiClient,
    required this.apiSettings,
    required this.officeSettings,
    required this.employeeRepository,
    required this.attendanceRepository,
    required this.leaveRepository,
    required this.locationService,
    this.locationSimulation,
    required this.connectivityService,
    required this.syncEngine,
    required this.connectivity,
    required this.sync,
    required this.dashboard,
    required this.attendance,
    required this.leave,
  });

  /// Release builds receive only the real Geolocator service. Debug/profile
  /// builds receive a switchable wrapper that still delegates to real GPS by
  /// default.
  static LocationServices createLocationServices({
    bool isReleaseMode = false,
    LocationService? realService,
    OfficeLocation Function()? officeProvider,
    bool enableSimulationInRelease = false,
  }) {
    final LocationService real = realService ?? GeolocatorLocationService();
    if (isReleaseMode && !enableSimulationInRelease) {
      return LocationServices(location: real, simulation: null);
    }
    final LocationSimulationViewModel simulation =
        LocationSimulationViewModel(
      realLocationService: real,
      officeProvider: officeProvider,
    );
    return LocationServices(location: simulation, simulation: simulation);
  }

  static Future<AppDependencies> create() async {
    final LocalStorage storage = HiveLocalStorage();
    await storage.init();

    final CompanyClock clock = CompanyClock();
    final ApiClient api = ApiClient();
    final ApiSettingsViewModel apiSettings = ApiSettingsViewModel(
      storage: storage,
      apiClient: api,
    );
    await apiSettings.init();
    final OfficeSettingsViewModel officeSettings = OfficeSettingsViewModel(
      storage: storage,
    );
    await officeSettings.init();
    final EmployeeRepository employees =
        EmployeeRepository(api: api, storage: storage);
    final AttendanceRepository attendanceRepo =
        AttendanceRepository(api: api, storage: storage, clock: clock);
    final LeaveRepository leaves =
        LeaveRepository(api: api, storage: storage);
    final LocationServices locationServices = createLocationServices(
      isReleaseMode: false,
      enableSimulationInRelease: true,
      officeProvider: () => officeSettings.office,
    );
    // DEBUG builds start with the simulated point placed inside the office
    // reference whenever any office coordinates are available (server-provided,
    // reviewer-entered, or auto-generated). Indoor phones often cannot obtain a
    // GPS fix, which would otherwise make Check In impossible. The switch on
    // the Attendance screen still turns simulation off to test real GPS, and
    // RELEASE never receives a simulation controller at all.
    if (locationServices.simulation != null && officeSettings.isConfigured) {
      locationServices.simulation!.setSimulationEnabled(false);
      locationServices.simulation!.useInsideOfficePreset(officeSettings.office);
    }
    final LocationService location = locationServices.location;
    final ConnectivityService connectivityService = ConnectivityService();
    final SyncEngine engine = SyncEngine(api: api, storage: storage);

    final ConnectivityViewModel connectivity =
        ConnectivityViewModel(connectivityService);
    await connectivity.init();

    final SyncViewModel sync = SyncViewModel(
      engine: engine,
      storage: storage,
      connectivity: connectivity,
    );
    await sync.init();

    final DashboardViewModel dashboard = DashboardViewModel(
      employeeRepository: employees,
      attendanceRepository: attendanceRepo,
      leaveRepository: leaves,
      connectivity: connectivity,
      clock: clock,
    );
    return AppDependencies(
      clock: clock,
      storage: storage,
      apiClient: api,
      apiSettings: apiSettings,
      officeSettings: officeSettings,
      employeeRepository: employees,
      attendanceRepository: attendanceRepo,
      leaveRepository: leaves,
      locationService: location,
      locationSimulation: locationServices.simulation,
      connectivityService: connectivityService,
      syncEngine: engine,
      connectivity: connectivity,
      sync: sync,
      dashboard: dashboard,
      attendance: AttendanceViewModel(
        attendanceRepository: attendanceRepo,
        employeeRepository: employees,
        officeSettings: officeSettings,
        connectivity: connectivity,
        sync: sync,
        locationService: location,
        clock: clock,
        // The Dashboard keeps its own published record list. Refresh it as soon
        // as an event is written so Check In / Check Out is visible without
        // restarting the app.
        onRecordsChanged: dashboard.reloadLocal,
      ),
      leave: LeaveViewModel(
        repository: leaves,
        connectivity: connectivity,
        clock: clock,
        sync: sync,
        // Keep the Dashboard's balance card in step with Leave immediately.
        onBalanceChanged: dashboard.reloadLocal,
      ),
    );
  }
}
