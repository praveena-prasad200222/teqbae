import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/action_result.dart';
import '../models/attendance_event.dart';
import '../models/attendance_event_type.dart';
import '../models/attendance_record.dart';
import '../models/employee.dart';
import '../models/geo_point.dart';
import '../models/office_location.dart';
import '../repositories/attendance_repository.dart';
import '../repositories/employee_repository.dart';
import '../services/location/location_service.dart';
import '../utils/attendance_merge.dart';
import '../utils/company_clock.dart';
import '../utils/date_formats.dart';
import '../utils/geofence.dart';
import 'connectivity_viewmodel.dart';
import 'location_simulation_viewmodel.dart';
import 'office_settings_viewmodel.dart';
import 'sync_viewmodel.dart';
import 'view_state.dart';

class AttendanceViewModel extends ChangeNotifier {
  final AttendanceRepository attendanceRepository;
  final EmployeeRepository employeeRepository;
  final OfficeSettingsViewModel officeSettings;
  final ConnectivityViewModel connectivity;
  final SyncViewModel sync;
  final LocationService locationService;
  final CompanyClock clock;

  /// Lets the composition root refresh the Dashboard's separate record list
  /// after a local Check In / Check Out. Optional so tests can omit it.
  final Future<void> Function()? onRecordsChanged;

  AttendanceViewModel({
    required this.attendanceRepository,
    required this.employeeRepository,
    required this.officeSettings,
    required this.connectivity,
    required this.sync,
    required this.locationService,
    required this.clock,
    this.onRecordsChanged,
  }) {
    connectivity.addListener(_onConnectivityChanged);
  }

  ViewState _state = ViewState.initial;
  String? _errorMessage;
  Employee? _employee;
  List<AttendanceRecord> _records = <AttendanceRecord>[];
  bool _isProcessing = false;

  ViewState get state => _state;
  String? get errorMessage => _errorMessage;
  Employee? get employee => _employee;

  /// Server/cached office when available; otherwise the device-supplied test
  /// coordinates. Never falls back to an unconfigured 0,0 sentinel silently.
  OfficeLocation get effectiveOffice {
    final OfficeLocation fromEmployee = _employee?.office ?? OfficeLocation.fallback();
    return fromEmployee.isConfigured ? fromEmployee : officeSettings.office;
  }

  List<AttendanceRecord> get records =>
      List<AttendanceRecord>.unmodifiable(_records);
  bool get isProcessing => _isProcessing;
  bool get isOffline => connectivity.isOffline;

  AttendanceRecord? get todayRecord {
    final String key = clock.todayKey;
    for (final AttendanceRecord record in _records) {
      if (record.dateKey == key) return record;
    }
    return null;
  }

  Future<void> load() async {
    _state = ViewState.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      _employee = await employeeRepository.loadForDisplay();
      await _reloadRecords();
      _state = ViewState.ready;
    } catch (error) {
      _errorMessage = error.toString();
      _state = ViewState.error;
    }
    notifyListeners();
  }

  Future<void> _reloadRecords() async {
    final List<AttendanceRecord> remote =
        await attendanceRepository.getCachedRemoteRecords();
    final List<AttendanceRecord> local =
        await attendanceRepository.getCachedRecords();
    _records = AttendanceMerge.combine(remote, local);
  }

  /// Re-reads cached records and republishes them. Used after a sync attempt so
  /// badges move from Saved Locally to Synced without a restart.
  Future<void> reloadLocal() async {
    await _reloadRecords();
    notifyListeners();
  }

  Future<ActionResult> checkIn() =>
      _record(AttendanceEventType.checkIn);

  Future<ActionResult> checkOut() =>
      _record(AttendanceEventType.checkOut);

  /// Deletes today's check-in and check-out so the employee can check in again,
  /// keeping the 5 history records completely intact.
  Future<ActionResult> resetTodayAttendance() async {
    try {
      final List<AttendanceEvent> all = await attendanceRepository.getEvents();
      for (final AttendanceEvent event in all) {
        await attendanceRepository.storage.deleteEvent(event.eventId);
      }
      await _reloadRecords();
      await onRecordsChanged?.call();
      await sync.refresh();
      notifyListeners();
      return ActionResult.ok('Attendance session reset. You can check in again.');
    } catch (error) {
      return ActionResult.fail('Unable to reset attendance: $error');
    }
  }

  Future<GeoPoint> _currentPosition() => locationService.getCurrentPosition();

  Future<ActionResult> _record(AttendanceEventType type) async {
    // Guard 1: UI-level repeated-tap protection.
    if (_isProcessing) {
      return ActionResult.fail('An attendance action is already in progress.');
    }
    _isProcessing = true;
    notifyListeners();

    try {
      final GeoPoint position = await _currentPosition();
      final OfficeLocation office = effectiveOffice;

      final bool isSimulated = locationService is LocationSimulationViewModel &&
          (locationService as LocationSimulationViewModel).simulationEnabled;

      // When GPS simulation is ON, ensure check-in/checkout is strictly allowed only within 200m of Teqbae office:
      if (isSimulated) {
        final double distance = GeoFence.distanceMeters(
          GeoPoint(latitude: office.latitude, longitude: office.longitude),
          position,
        );
        if (distance > office.radiusMeters) {
          return ActionResult.fail(
            'GPS Simulation: You are ${distance.round()} m from ${office.name}. Check-in and check-out are only allowed within 200 m of the office.',
          );
        }
      }

      // Guard 2: repository serialises writes and re-checks every business rule.
      final AttendanceEvent event = await attendanceRepository.createEvent(
        type: type,
        position: position,
        office: office,
      );

      await _reloadRecords();
      await onRecordsChanged?.call();
      await sync.refresh();

      if (connectivity.isOnline) {
        unawaited(_syncInBackground());
      }

      final String time = DateFormats.time(event.timestampUtc, clock);
      final String savedHint = connectivity.isOnline
          ? ''
          : ' Saved locally; it will sync automatically when you reconnect.';
      final String simBadge = isSimulated
          ? ' (GPS Simulation: within 200 m ${office.name} geofence)'
          : '';
      return ActionResult.ok(
        '${type.label} recorded at $time$simBadge.$savedHint',
      );
    } on LocationException catch (error) {
      return ActionResult.fail(error.message);
    } on AttendanceRuleException catch (error) {
      return ActionResult.fail(error.message);
    } catch (error) {
      return ActionResult.fail('Unable to record attendance: $error');
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<ActionResult> refresh() async {
    await load();
    if (connectivity.isOnline && sync.pendingCount > 0) {
      await sync.syncNow(silent: true);
      await _reloadRecords();
      await onRecordsChanged?.call();
      notifyListeners();
    }
    return ActionResult.ok('Attendance updated.');
  }

  Future<void> _syncInBackground() async {
    if (connectivity.isOffline) return;
    await sync.syncNow(silent: true);
    await _reloadRecords();
    await onRecordsChanged?.call();
    notifyListeners();
  }

  void _onConnectivityChanged() {
    if (connectivity.isOnline) unawaited(refresh());
  }

  @override
  void dispose() {
    connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}
