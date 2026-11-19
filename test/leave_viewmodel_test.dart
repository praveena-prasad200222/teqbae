import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';
import 'package:teqbae/models/action_result.dart';
import 'package:teqbae/models/leave_balance.dart';
import 'package:teqbae/models/leave_request.dart';
import 'package:teqbae/models/leave_type.dart';
import 'package:teqbae/models/sync_status.dart';
import 'package:teqbae/providers/connectivity_viewmodel.dart';
import 'package:teqbae/providers/leave_viewmodel.dart';
import 'package:teqbae/providers/view_state.dart';
import 'package:teqbae/repositories/leave_repository.dart';
import 'package:teqbae/screens/leave_screen.dart';
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
  Object? balanceFailure;
  int submitCalls = 0;

  @override
  Future<LeaveBalance> fetchLeaveBalance() {
    if (balanceFailure != null) {
      return Future<LeaveBalance>.error(balanceFailure!);
    }
    return super.fetchLeaveBalance();
  }

  @override
  Future<LeaveRequest> submitLeaveRequest({
    required LeaveType type,
    required String startDate,
    required String endDate,
    required String reason,
    required int days,
    required String requestId,
  }) {
    submitCalls++;
    return super.submitLeaveRequest(
      type: type,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      days: days,
      requestId: requestId,
    );
  }
}

void main() {
  late InMemoryLocalStorage storage;
  late _ControlledApiClient api;
  late _FakeConnectivityService connectivityService;
  late ConnectivityViewModel connectivity;
  late CompanyClock clock;
  late LeaveViewModel vm;

  setUp(() {
    storage = InMemoryLocalStorage();
    api = _ControlledApiClient();
    connectivityService = _FakeConnectivityService();
    connectivity = ConnectivityViewModel(connectivityService);
    clock = CompanyClock(
      offsetMinutes: 330,
      utcNowProvider: () => DateTime.utc(2026, 1, 15, 4, 0),
    );
    vm = LeaveViewModel(
      repository: LeaveRepository(api: api, storage: storage),
      connectivity: connectivity,
      clock: clock,
    );
  });

  test('sample balance is stored and displayed when the API fails', () async {
    api.balanceFailure = ApiNetworkException('Connection timed out.');

    await vm.load();

    expect(vm.state, ViewState.ready);
    expect(vm.balance, LeaveBalance.sample);
    expect(vm.balance!.casual, 12);
    expect(vm.balance!.sick, 6);
    expect(vm.balance!.total, 18);
    expect(storage.balance, LeaveBalance.sample);
    expect(vm.refreshError, contains('retry'));
  });

  test('API balance overwrites the locally stored sample', () async {
    api.leaveBalance = const LeaveBalance(casual: 9, sick: 4);

    await vm.load();

    expect(vm.balance, const LeaveBalance(casual: 9, sick: 4));
    expect(storage.balance, const LeaveBalance(casual: 9, sick: 4));
    expect(vm.refreshError, isNull);
  });

  test('missing JSON fields fall back to sample but explicit zero is kept', () {
    expect(LeaveBalance.fromJson(<String, dynamic>{}), LeaveBalance.sample);
    expect(
      LeaveBalance.fromJson(<String, dynamic>{'casual': 0, 'sick': 6}),
      const LeaveBalance(casual: 0, sick: 6),
    );
  });

  test('past start date is rejected by the ViewModel before submission', () async {
    final result = await vm.submit(
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 14),
      endDate: DateTime(2026, 1, 16),
      reason: 'Family function at home.',
    );

    expect(result.success, isFalse);
    expect(result.message, contains('Start date cannot be before'));
    expect(api.submitCalls, 0);
  });

  test('end date before start date is rejected by the ViewModel', () async {
    final result = await vm.submit(
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 17),
      endDate: DateTime(2026, 1, 16),
      reason: 'Family function at home.',
    );

    expect(result.success, isFalse);
    expect(result.message, contains('End date cannot be before'));
    expect(api.submitCalls, 0);
  });

  test('online submission queues locally with a stable request id', () async {
    await vm.load();

    final result = await vm.submit(
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 15),
      endDate: DateTime(2026, 1, 16),
      reason: 'Family function at home.',
    );

    expect(result.success, isTrue);
    expect(result.message, startsWith('Leave added successfully!'));
    expect(result.message, contains('Pending Sync'));
    expect(api.submitCalls, 0);
    expect(storage.requests, hasLength(1));
    expect(storage.requests.single.id, startsWith('LRV-LOCAL-'));
    expect(storage.requests.single.syncStatus, SyncStatus.pending);
    expect(vm.pendingSyncCount, 1);
    expect(vm.balance, const LeaveBalance(casual: 10, sick: 6));
    expect(storage.balance, const LeaveBalance(casual: 10, sick: 6));
  });

  test('editing updates the existing request instead of adding a duplicate',
      () async {
    await vm.load();
    await vm.submit(
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 15),
      endDate: DateTime(2026, 1, 15),
      reason: 'Family function at home.',
    );
    final String id = storage.requests.single.id;

    final result = await vm.updateRequest(
      requestId: id,
      type: LeaveType.sick,
      startDate: DateTime(2026, 1, 20),
      endDate: DateTime(2026, 1, 21),
      reason: 'Medical appointment and recovery.',
    );

    expect(result.success, isTrue);
    expect(result.message, contains('updated'));
    expect(storage.requests, hasLength(1));
    expect(storage.requests.single.id, id);
    expect(storage.requests.single.type, LeaveType.sick);
    expect(storage.requests.single.startDate, '2026-01-20');
    expect(storage.requests.single.endDate, '2026-01-21');
    expect(storage.requests.single.days, 2);
    expect(storage.requests.single.syncStatus, SyncStatus.pending);
    expect(vm.requests, hasLength(1));
    expect(vm.balance, const LeaveBalance(casual: 12, sick: 4));
    expect(storage.balance, const LeaveBalance(casual: 12, sick: 4));
  });

  test('editing validates overlap with other requests', () async {
    await vm.load();
    await vm.submit(
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 15),
      endDate: DateTime(2026, 1, 15),
      reason: 'Family function at home.',
    );
    await vm.submit(
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 17),
      endDate: DateTime(2026, 1, 17),
      reason: 'Personal work at home.',
    );
    final LeaveRequest second = vm.requests
        .firstWhere((LeaveRequest r) => r.startDate == '2026-01-17');

    final result = await vm.updateRequest(
      requestId: second.id,
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 15),
      endDate: DateTime(2026, 1, 15),
      reason: 'Family function at home.',
    );

    expect(result.success, isFalse);
    expect(result.message, contains('overlap'));
    expect(storage.requests, hasLength(2));
    expect(
      storage.requests
          .firstWhere((LeaveRequest r) => r.id == second.id)
          .startDate,
      '2026-01-17',
    );
  });

  test('deleting removes the local request and queues a tombstone', () async {
    await vm.load();
    await vm.submit(
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 15),
      endDate: DateTime(2026, 1, 16),
      reason: 'Family function at home.',
    );
    final String id = storage.requests.single.id;

    final result = await vm.deleteRequest(id);

    expect(result.success, isTrue);
    expect(result.message, contains('deleted'));
    expect(storage.requests, isEmpty);
    expect(vm.requests, isEmpty);
    expect(storage.leaveDeletionQueue, contains(id));
    expect(vm.pendingSyncCount, 0);
  });

  test('offline edit and delete stay local without submitting', () async {
    await vm.load();
    connectivity.setOnlineState(false);
    await vm.submit(
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 15),
      endDate: DateTime(2026, 1, 15),
      reason: 'Family function at home.',
    );
    final String id = storage.requests.single.id;

    final ActionResult edit = await vm.updateRequest(
      requestId: id,
      type: LeaveType.sick,
      startDate: DateTime(2026, 1, 22),
      endDate: DateTime(2026, 1, 22),
      reason: 'Medical appointment at hospital.',
    );
    expect(edit.success, isTrue);
    expect(storage.requests.single.type, LeaveType.sick);
    expect(storage.requests.single.syncStatus, SyncStatus.pending);

    final ActionResult delete = await vm.deleteRequest(id);
    expect(delete.success, isTrue);
    expect(storage.requests, isEmpty);
    expect(storage.leaveDeletionQueue, contains(id));
    expect(api.submitCalls, 0);
  });

  test('offline submission is saved locally as Pending Sync', () async {
    await vm.load();
    connectivity.setOnlineState(false);

    final result = await vm.submit(
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 15),
      endDate: DateTime(2026, 1, 16),
      reason: 'Family function at home.',
    );

    expect(result.success, isTrue);
    expect(result.message, contains('Pending Sync'));
    expect(api.submitCalls, 0);
    expect(storage.requests, hasLength(1));
    expect(storage.requests.single.syncStatus, SyncStatus.pending);
    expect(vm.pendingSyncCount, 1);
  });

  test('server errors cannot block a foreground submission', () async {
    await vm.load();
    api.leaveError = ApiValidationException('Reason must mention the event.');

    final result = await vm.submit(
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 15),
      endDate: DateTime(2026, 1, 16),
      reason: 'Family function at home.',
    );

    expect(result.success, isTrue);
    expect(result.message, contains('Pending Sync'));
    expect(result.message, isNot(contains('Reason must mention')));
    expect(storage.requests.single.syncStatus, SyncStatus.pending);
    expect(vm.pendingSyncCount, 1);
  });

  test('5xx errors cannot block a foreground submission', () async {
    await vm.load();
    api.leaveError = ApiServerException('Mock server unavailable.');

    final result = await vm.submit(
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 15),
      endDate: DateTime(2026, 1, 16),
      reason: 'Family function at home.',
    );

    expect(result.success, isTrue);
    expect(result.message, contains('Pending Sync'));
    expect(result.message, isNot(contains('Mock server unavailable')));
    expect(storage.requests.single.syncStatus, SyncStatus.pending);
    expect(vm.pendingSyncCount, 1);
  });

  test('API reachability failure never shows a generic connection message',
      () async {
    await vm.load();
    api.leaveError = ApiNetworkException(
      'Cannot reach the API server at http://192.168.1.10:8090.',
    );

    final result = await vm.submit(
      type: LeaveType.casual,
      startDate: DateTime(2026, 1, 15),
      endDate: DateTime(2026, 1, 16),
      reason: 'Family function at home.',
    );

    expect(result.success, isTrue);
    expect(result.message, contains('Pending Sync'));
    expect(result.message, isNot(contains('192.168.1.10')));
    expect(result.message.toLowerCase(), isNot(contains('connection lost')));
    expect(storage.requests.single.syncStatus, SyncStatus.pending);
    expect(vm.pendingSyncCount, 1);
  });

  testWidgets('leave calendar disables dates before the company today',
      (WidgetTester tester) async {
    connectivityService.setOnline(false);
    await vm.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<ConnectivityViewModel>.value(
              value: connectivity),
          ChangeNotifierProvider<LeaveViewModel>.value(value: vm),
        ],
        child: const MaterialApp(
          home: Scaffold(body: LeaveScreen()),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Start date'));
    await tester.pumpAndSettle();

    final DatePickerDialog picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(picker.firstDate, DateTime(2026, 1, 15));
  });
}
