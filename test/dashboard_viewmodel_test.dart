import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teqbae/models/attendance_event.dart';
import 'package:teqbae/models/attendance_event_type.dart';
import 'package:teqbae/models/attendance_record.dart';
import 'package:teqbae/models/attendance_status.dart';
import 'package:teqbae/models/employee.dart';
import 'package:teqbae/models/leave_balance.dart';
import 'package:teqbae/models/sync_status.dart';
import 'package:teqbae/providers/connectivity_viewmodel.dart';
import 'package:teqbae/providers/dashboard_viewmodel.dart';
import 'package:teqbae/providers/view_state.dart';
import 'package:teqbae/repositories/attendance_repository.dart';
import 'package:teqbae/repositories/employee_repository.dart';
import 'package:teqbae/repositories/leave_repository.dart';
import 'package:teqbae/services/api/api_exceptions.dart';
import 'package:teqbae/services/network/connectivity_service.dart';
import 'package:teqbae/utils/company_clock.dart';

import 'helpers/fake_api_client.dart';
import 'helpers/in_memory_local_storage.dart';

class _FakeConnectivityService implements ConnectivityService {
  _FakeConnectivityService() : _online = true;

  bool _online;
  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  void setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    _controller.add(value);
  }
}

class _ControlledApiClient extends FakeApiClient {
  Completer<Employee>? employeeGate;
  Object? employeeFailure;
  Object? attendanceFailure;
  Object? balanceFailure;

  int employeeCalls = 0;
  int attendanceCalls = 0;
  int balanceCalls = 0;

  @override
  Future<Employee> fetchEmployee() {
    employeeCalls++;
    if (employeeFailure != null) {
      return Future<Employee>.error(employeeFailure!);
    }
    if (employeeGate != null) return employeeGate!.future;
    return super.fetchEmployee();
  }

  @override
  Future<List<AttendanceRecord>> fetchAttendance(String monthKey) {
    attendanceCalls++;
    if (attendanceFailure != null) {
      return Future<List<AttendanceRecord>>.error(attendanceFailure!);
    }
    return super.fetchAttendance(monthKey);
  }

  @override
  Future<LeaveBalance> fetchLeaveBalance() {
    balanceCalls++;
    if (balanceFailure != null) {
      return Future<LeaveBalance>.error(balanceFailure!);
    }
    return super.fetchLeaveBalance();
  }
}

void main() {
  late InMemoryLocalStorage storage;
  late _ControlledApiClient api;
  late _FakeConnectivityService connectivityService;
  late ConnectivityViewModel connectivity;
  late CompanyClock clock;
  late DashboardViewModel vm;

  setUp(() {
    storage = InMemoryLocalStorage();
    api = _ControlledApiClient();
    connectivityService = _FakeConnectivityService();
    connectivity = ConnectivityViewModel(connectivityService);
    clock = CompanyClock(
      offsetMinutes: 330,
      utcNowProvider: () => DateTime.utc(2026, 1, 15, 4, 0),
    );
    vm = DashboardViewModel(
      employeeRepository: EmployeeRepository(api: api, storage: storage),
      attendanceRepository: AttendanceRepository(
        api: api,
        storage: storage,
        clock: clock,
      ),
      leaveRepository: LeaveRepository(api: api, storage: storage),
      connectivity: connectivity,
      clock: clock,
    );
  });

  Future<void> seedCache() async {
    storage.employee = Employee.fallback();
    storage.balance = const LeaveBalance(casual: 12, sick: 6);
    final List<AttendanceRecord> records = <AttendanceRecord>[
      const AttendanceRecord(dateKey: '2026-01-15', checkIn: null, checkOut: null),
    ];
    await storage.putCachedRemoteRecords(records);
    api.attendanceRecords = records;
  }

  test('publishes cached data before the API responds', () async {
    await seedCache();
    final Completer<Employee> gate = Completer<Employee>();
    api.employeeGate = gate;

    final Future<void> loading = vm.load();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(vm.state, ViewState.ready);
    expect(vm.employee, isNotNull);
    expect(vm.balance, const LeaveBalance(casual: 12, sick: 6));
    expect(vm.latestRecords, hasLength(1));
    expect(vm.isRefreshing, isTrue);

    final Employee fallback = Employee.fallback();
    final Employee remote = Employee(
      id: fallback.id,
      name: 'Updated Name',
      department: fallback.department,
      designation: fallback.designation,
      email: fallback.email,
      office: fallback.office,
    );
    gate.complete(remote);
    await loading;

    expect(vm.employee!.name, 'Updated Name');
    expect(vm.isRefreshing, isFalse);
    expect(vm.refreshError, isNull);
  });

  test('API failures keep cached data visible with a retryable message', () async {
    await seedCache();
    api.employeeFailure = ApiNetworkException('Connection timed out.');
    api.attendanceFailure = ApiNetworkException('Connection timed out.');
    api.balanceFailure = ApiNetworkException('Connection timed out.');

    await vm.load();

    expect(vm.state, ViewState.ready);
    expect(vm.employee, isNotNull);
    expect(vm.balance, const LeaveBalance(casual: 12, sick: 6));
    expect(vm.latestRecords, hasLength(1));
    expect(vm.isRefreshing, isFalse);
    expect(vm.refreshError, contains('retry'));
  });

  test('offline load skips API calls and never hangs on loading', () async {
    await seedCache();
    connectivity.setOnlineState(false);

    await vm.load();

    expect(vm.state, ViewState.ready);
    expect(vm.isOffline, isTrue);
    expect(vm.isRefreshing, isFalse);
    expect(vm.refreshError, contains('Offline'));
    expect(api.employeeCalls, 0);
    expect(api.attendanceCalls, 0);
    expect(api.balanceCalls, 0);
  });

  test('latestRecords exposes only the five newest attendance records', () async {
    final List<AttendanceRecord> records = <AttendanceRecord>[
      for (int day = 10; day <= 16; day++)
        AttendanceRecord(
          dateKey: '2026-01-$day',
          checkIn: null,
          checkOut: null,
        ),
    ];
    await storage.putCachedRemoteRecords(records);
    api.attendanceRecords = records;

    await vm.load();

    expect(vm.records, hasLength(7));
    expect(vm.latestRecords, hasLength(5));
    expect(
      vm.latestRecords.map((AttendanceRecord r) => r.dateKey).toList(),
      <String>['2026-01-16', '2026-01-15', '2026-01-14', '2026-01-13', '2026-01-12'],
    );
  });

  test('reloadLocal publishes a local check-in without a network refresh',
      () async {
    await seedCache();
    await vm.load();
    expect(vm.todayRecord?.checkIn, isNull);

    await storage.putEvent(AttendanceEvent.create(
      type: AttendanceEventType.checkIn,
      timestampUtc: DateTime.utc(2026, 1, 15, 4, 30),
      latitude: 10.000000,
      longitude: 76.000000,
      dateKey: '2026-01-15',
      sequence: 1,
    ));

    await vm.reloadLocal();

    expect(vm.todayRecord?.checkIn, isNotNull);
    expect(vm.todayRecord?.status, AttendanceStatus.checkedIn);
    expect(vm.todayRecord?.syncStatus, SyncStatus.pending);
  });

  test('concurrent load and refresh share one background future', () async {
    await seedCache();
    final Completer<Employee> gate = Completer<Employee>();
    api.employeeGate = gate;

    final Future<void> first = vm.load();
    final Future<void> second = vm.refresh();

    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(api.employeeCalls, 1);

    gate.complete(Employee.fallback());
    await Future.wait<void>(<Future<void>>[first, second]);
    expect(vm.isRefreshing, isFalse);
  });
}
