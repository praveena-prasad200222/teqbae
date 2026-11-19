import 'package:flutter_test/flutter_test.dart';

import 'package:teqbae/models/attendance_event.dart';
import 'package:teqbae/models/attendance_event_type.dart';
import 'package:teqbae/models/geo_point.dart';
import 'package:teqbae/models/leave_type.dart';
import 'package:teqbae/models/office_location.dart';
import 'package:teqbae/models/sync_status.dart';
import 'package:teqbae/repositories/attendance_repository.dart';
import 'package:teqbae/repositories/leave_repository.dart';
import 'package:teqbae/services/api/api_exceptions.dart';
import 'package:teqbae/services/sync/sync_engine.dart';
import 'package:teqbae/utils/company_clock.dart';

import 'helpers/fake_api_client.dart';
import 'helpers/in_memory_local_storage.dart';

final CompanyClock _clock = CompanyClock(
  offsetMinutes: 330,
  utcNowProvider: () => DateTime.utc(2026, 1, 15, 4, 0),
);

final OfficeLocation _office = OfficeLocation(
  name: 'Test Office',
  latitude: 10.000000,
  longitude: 76.000000,
  radiusMeters: 200,
  timezoneOffsetMinutes: 330,
);

const GeoPoint _inside = GeoPoint(latitude: 10.000000, longitude: 76.000000);

void main() {
  late InMemoryLocalStorage storage;
  late FakeApiClient api;
  late AttendanceRepository repository;
  late SyncEngine engine;

  setUp(() {
    storage = InMemoryLocalStorage();
    api = FakeApiClient();
    repository = AttendanceRepository(api: api, storage: storage, clock: _clock);
    engine = SyncEngine(api: api, storage: storage);
  });

  Future<Object> tryCreate(AttendanceEventType type, {String dateKey = '2026-01-15'}) async {
    try {
      return await repository.createEvent(
        type: type,
        position: _inside,
        office: _office,
        dateKey: dateKey,
      );
    } catch (error) {
      return error;
    }
  }

  test('repeated simultaneous taps create only one check-in event', () async {
    final List<Object> outcomes = await Future.wait<Object>(<Future<Object>>[
      tryCreate(AttendanceEventType.checkIn),
      tryCreate(AttendanceEventType.checkIn),
      tryCreate(AttendanceEventType.checkIn),
    ]);

    final List<AttendanceEvent> events = await storage.getEvents();
    expect(events.length, 1);
    expect(outcomes.whereType<AttendanceEvent>().length, 1);
    expect(outcomes.whereType<AttendanceRuleException>().length, 2);
    expect(events.first.syncStatus, SyncStatus.pending);
  });

  test('check-out without check-in is rejected by repository', () async {
    final Object outcome = await tryCreate(AttendanceEventType.checkOut);
    expect(outcome, isA<AttendanceRuleException>());
    expect((await storage.getEvents()).isEmpty, isTrue);
  });

  test('pending attendance survives storage and syncs in creation order',
      () async {
    await repository.createEvent(
      type: AttendanceEventType.checkIn,
      position: _inside,
      office: _office,
      dateKey: '2026-01-14',
    );
    await repository.createEvent(
      type: AttendanceEventType.checkOut,
      position: _inside,
      office: _office,
      dateKey: '2026-01-14',
    );

    // Simulate an app restart: a new repository over the same persisted store.
    final AttendanceRepository reopened = AttendanceRepository(
      api: api,
      storage: storage,
      clock: _clock,
    );
    final List<AttendanceEvent> restored = await reopened.getEvents();
    expect(restored.length, 2);
    expect(restored.every((e) => e.syncStatus == SyncStatus.pending), isTrue);

    final SyncSummary summary = await engine.syncPending();

    expect(summary.synced, 2);
    expect(summary.pending, 0);
    expect(
      api.submittedEvents.map((e) => e.type).toList(),
      <AttendanceEventType>[
        AttendanceEventType.checkIn,
        AttendanceEventType.checkOut,
      ],
    );
    final List<AttendanceEvent> synced = await storage.getEvents();
    expect(synced.every((e) => e.syncStatus == SyncStatus.synced), isTrue);
    expect(storage.lastSync, isNotNull);
  });

  test('network failure keeps local events pending', () async {
    await repository.createEvent(
      type: AttendanceEventType.checkIn,
      position: _inside,
      office: _office,
    );
    api.attendanceError = ApiNetworkException('offline');

    final SyncSummary summary = await engine.syncPending();

    expect(summary.failed, 1);
    final List<AttendanceEvent> events = await storage.getEvents();
    expect(events.length, 1);
    expect(events.first.syncStatus, SyncStatus.failed);
    expect(events.first.attempts, 1);
    expect(storage.lastSync, isNull);
  });

  test('server conflict marks the event Rejected without deleting it', () async {
    await repository.createEvent(
      type: AttendanceEventType.checkIn,
      position: _inside,
      office: _office,
    );
    api.attendanceError =
        ApiConflictException('Attendance already exists for this date.');

    await engine.syncPending();

    final List<AttendanceEvent> events = await storage.getEvents();
    expect(events.length, 1);
    expect(events.first.syncStatus, SyncStatus.rejected);
    expect(events.first.lastError, contains('already exists'));
  });

  test('retry with the same eventId reuses the server receipt', () async {
    final AttendanceEvent event = await repository.createEvent(
      type: AttendanceEventType.checkIn,
      position: _inside,
      office: _office,
    );
    api.attendanceError = ApiNetworkException('timeout after server accepted');
    await engine.syncPending();
    expect((await storage.getEvents()).first.syncStatus, SyncStatus.failed);

    api.attendanceError = null;
    await engine.syncPending();

    final AttendanceEvent retried = (await storage.getEvents()).first;
    expect(retried.eventId, event.eventId);
    expect(retried.attempts, 2);
    expect(retried.syncStatus, SyncStatus.synced);
    expect(api.serverIdsByEvent.length, 1);
    expect(retried.serverEventId, isNotNull);
  });

  test('pending leave request syncs on reconnect without duplicates', () async {
    final LeaveRepository leaves =
        LeaveRepository(api: api, storage: storage);
    final pending = await leaves.queue(
      type: LeaveType.casual,
      startDate: '2026-01-15',
      endDate: '2026-01-16',
      reason: 'Family function at home.',
      days: 2,
    );

    api.leaveError = ApiNetworkException('offline');
    SyncSummary summary = await engine.syncPending();
    expect(summary.failed, 1);
    expect(storage.requests.single.syncStatus, SyncStatus.failed);

    api.leaveError = null;
    summary = await engine.syncPending();

    expect(summary.synced, 1);
    expect(summary.pending, 0);
    expect(storage.requests, hasLength(1));
    expect(storage.requests.single.id, pending.id);
    expect(storage.requests.single.syncStatus, SyncStatus.synced);
    // Two attempts were made, both with the same stable idempotency key.
    expect(api.submittedLeaveRequests, hasLength(2));
    expect(
      api.submittedLeaveRequests
          .map((Map<String, Object?> call) => call['requestId'])
          .toSet(),
      <Object?>{pending.id},
    );
  });

  test('422 leave response marks the local request Rejected with the message',
      () async {
    final LeaveRepository leaves =
        LeaveRepository(api: api, storage: storage);
    await leaves.queue(
      type: LeaveType.casual,
      startDate: '2026-01-15',
      endDate: '2026-01-16',
      reason: 'Family function at home.',
      days: 2,
    );
    api.leaveError =
        ApiValidationException('Manager approval quota exceeded.');

    final SyncSummary summary = await engine.syncPending();

    expect(summary.rejected, 1);
    expect(summary.pending, 0);
    expect(storage.requests, hasLength(1));
    expect(storage.requests.single.syncStatus, SyncStatus.rejected);
    expect(
      storage.requests.single.lastError,
      'Manager approval quota exceeded.',
    );
  });
}
