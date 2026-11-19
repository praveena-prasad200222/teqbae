import '../models/attendance_event.dart';
import '../models/attendance_event_type.dart';
import '../models/attendance_record.dart';
import '../models/geo_point.dart';
import '../models/office_location.dart';
import '../services/api/api_client.dart';
import '../services/storage/local_storage.dart';
import '../utils/attendance_rules.dart';
import '../utils/company_clock.dart';

class AttendanceRuleException implements Exception {
  final String message;

  AttendanceRuleException(this.message);

  @override
  String toString() => message;
}

/// Owns local attendance events, business-rule enforcement and remote reads.
class AttendanceRepository {
  final ApiClient api;
  final LocalStorage storage;
  final CompanyClock clock;

  AttendanceRepository({
    required this.api,
    required this.storage,
    required this.clock,
  });

  AttendanceRules get rules => AttendanceRules(clock: clock);

  Future<List<AttendanceEvent>> getEvents() => storage.getEvents();

  Future<AttendanceEvent?> getEvent(String eventId) =>
      storage.getEvent(eventId);

  /// Cached history is derived from locally persisted events, so it survives
  /// app restarts and works with no connection at all.
  Future<List<AttendanceRecord>> getCachedRecords() async =>
      AttendanceRecord.build(await storage.getEvents());

  /// Throws on failure; caller decides whether to fall back to cached data.
  Future<List<AttendanceRecord>> fetchMonth(String monthKey) =>
      api.fetchAttendance(monthKey);

  Future<List<AttendanceRecord>> getCachedRemoteRecords() =>
      storage.getCachedRemoteRecords();

  Future<void> cacheRemoteRecords(List<AttendanceRecord> records) =>
      storage.putCachedRemoteRecords(records);

  /// Creates and persists one valid event.
  ///
  /// A serial queue plus the rule check makes repeated taps safe: even two
  /// simultaneous calls cannot both create a check-in for the same day.
  Future<AttendanceEvent> createEvent({
    required AttendanceEventType type,
    required GeoPoint position,
    required OfficeLocation office,
    String? dateKey,
  }) {
    return _synchronized(() async {
      final List<AttendanceEvent> events = await storage.getEvents();
      final AttendanceDecision decision = rules.evaluate(
        events: events,
        type: type,
        position: position,
        office: office,
        dateKey: dateKey,
      );
      if (!decision.allowed) {
        throw AttendanceRuleException(decision.message ?? 'Action not allowed.');
      }

      final int nextSequence = events.isEmpty
          ? 1
          : events
                  .map((AttendanceEvent e) => e.sequence)
                  .reduce((int a, int b) => a > b ? a : b) +
              1;

      final AttendanceEvent event = AttendanceEvent.create(
        type: type,
        timestampUtc: clock.utcNow,
        latitude: position.latitude,
        longitude: position.longitude,
        dateKey: dateKey ?? clock.todayKey,
        sequence: nextSequence,
      );

      // Idempotency guard: never overwrite an event with the same ID.
      final AttendanceEvent? existing = await storage.getEvent(event.eventId);
      if (existing != null) return existing;
      await storage.putEvent(event);
      return event;
    });
  }

  Future<void> saveEvent(AttendanceEvent event) => storage.putEvent(event);

  // Simple serial execution queue (no extra dependency required).
  Future<void> _tail = Future<void>.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final Future<T> result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
