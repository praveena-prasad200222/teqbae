import 'package:flutter_test/flutter_test.dart';
import 'package:teqbae/models/action_result.dart';
import 'package:teqbae/models/attendance_event.dart';
import 'package:teqbae/models/attendance_event_type.dart';
import 'package:teqbae/models/sync_status.dart';
import 'package:teqbae/providers/connectivity_viewmodel.dart';
import 'package:teqbae/providers/sync_viewmodel.dart';
import 'package:teqbae/services/api/api_exceptions.dart';
import 'package:teqbae/services/network/connectivity_service.dart';
import 'package:teqbae/services/sync/sync_engine.dart';

import 'helpers/fake_api_client.dart';
import 'helpers/in_memory_local_storage.dart';

void main() {
  late InMemoryLocalStorage storage;
  late FakeApiClient api;
  late ConnectivityViewModel connectivity;
  late SyncViewModel sync;

  setUp(() async {
    storage = InMemoryLocalStorage();
    await storage.putEvent(AttendanceEvent.create(
      type: AttendanceEventType.checkIn,
      timestampUtc: DateTime.utc(2026, 1, 15, 4),
      latitude: 10.000000,
      longitude: 76.000000,
      dateKey: '2026-01-15',
      sequence: 1,
    ));
    api = FakeApiClient();
    connectivity = ConnectivityViewModel(ConnectivityService());
    sync = SyncViewModel(
      engine: SyncEngine(api: api, storage: storage),
      storage: storage,
      connectivity: connectivity,
    );
    await sync.refresh();
  });

  test('unreachable API reports the failure with the configured URL', () async {
    api.attendanceError = ApiNetworkException(
      'Cannot reach http://10.0.2.2:8090 within 8s.',
    );

    final ActionResult result = await sync.syncNow();

    expect(result.success, isFalse);
    expect(result.message, contains('failed to sync'));
    expect(result.message, contains('Cannot reach'));
    expect(sync.pendingCount, 1);
    expect(storage.events.values.single.syncStatus, SyncStatus.failed);
  });

  test('offline sync is reported as a failure and keeps the pending record',
      () async {
    connectivity.setOnlineState(false);

    final ActionResult result = await sync.syncNow();

    expect(result.success, isFalse);
    expect(result.message.toLowerCase(), contains('offline'));
    expect(sync.pendingCount, 1);
    expect(storage.events.values.single.syncStatus, SyncStatus.pending);
  });

  test('successful sync reports that everything is up to date', () async {
    final ActionResult result = await sync.syncNow();

    expect(result.success, isTrue);
    expect(result.message, contains('up to date'));
    expect(sync.pendingCount, 0);
    expect(storage.events.values.single.syncStatus, SyncStatus.synced);
  });
}
