import 'attendance_event.dart';
import 'attendance_event_type.dart';
import 'attendance_status.dart';
import 'sync_status.dart';

/// One working day of attendance, derived from local events.
class AttendanceRecord {
  final String dateKey;
  final AttendanceEvent? checkIn;
  final AttendanceEvent? checkOut;

  const AttendanceRecord({
    required this.dateKey,
    required this.checkIn,
    required this.checkOut,
  });

  AttendanceStatus get status {
    if (checkOut != null) return AttendanceStatus.checkedOut;
    if (checkIn != null) return AttendanceStatus.checkedIn;
    return AttendanceStatus.notCheckedIn;
  }

  DateTime? get checkInAt => checkIn?.timestampUtc;
  DateTime? get checkOutAt => checkOut?.timestampUtc;

  Duration? workingDurationAt([DateTime? nowUtc]) {
    final DateTime? start = checkInAt;
    if (start == null) return null;
    final DateTime? end = checkOutAt ?? nowUtc;
    if (end == null || end.isBefore(start)) return null;
    return end.difference(start);
  }

  Duration? get workingDuration => workingDurationAt();

  /// A day is only fully synced when all events present are synced.
  SyncStatus get syncStatus {
    final List<AttendanceEvent> events = <AttendanceEvent>[
      ?checkIn,
      ?checkOut,
    ];
    if (events.isEmpty) return SyncStatus.synced;
    if (events.any((AttendanceEvent e) => e.syncStatus == SyncStatus.rejected)) {
      return SyncStatus.rejected;
    }
    if (events.any((AttendanceEvent e) => e.syncStatus == SyncStatus.failed)) {
      return SyncStatus.failed;
    }
    if (events.any((AttendanceEvent e) => e.syncStatus == SyncStatus.pending)) {
      return SyncStatus.pending;
    }
    return SyncStatus.synced;
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    final dynamic checkInJson = json['checkIn'];
    final dynamic checkOutJson = json['checkOut'];
    return AttendanceRecord(
      dateKey: json['dateKey'] as String,
      checkIn: checkInJson is Map<String, dynamic>
          ? AttendanceEvent.fromJson(checkInJson)
          : null,
      checkOut: checkOutJson is Map<String, dynamic>
          ? AttendanceEvent.fromJson(checkOutJson)
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'dateKey': dateKey,
        'checkIn': checkIn?.toJson(),
        'checkOut': checkOut?.toJson(),
      };

  /// Groups events into one record per company-local day.
  static List<AttendanceRecord> build(List<AttendanceEvent> events) {
    final Map<String, AttendanceRecord> byDay = <String, AttendanceRecord>{};
    final List<AttendanceEvent> sorted = List<AttendanceEvent>.from(events)
      ..sort((AttendanceEvent a, AttendanceEvent b) =>
          a.sequence.compareTo(b.sequence));

    for (final AttendanceEvent event in sorted) {
      final AttendanceRecord existing =
          byDay.putIfAbsent(event.dateKey, () => AttendanceRecord(
                dateKey: event.dateKey,
                checkIn: null,
                checkOut: null,
              ));
      if (event.type == AttendanceEventType.checkIn &&
          existing.checkIn == null) {
        byDay[event.dateKey] = AttendanceRecord(
          dateKey: existing.dateKey,
          checkIn: event,
          checkOut: existing.checkOut,
        );
      } else if (event.type == AttendanceEventType.checkOut &&
          existing.checkOut == null) {
        byDay[event.dateKey] = AttendanceRecord(
          dateKey: existing.dateKey,
          checkIn: existing.checkIn,
          checkOut: event,
        );
      }
    }

    final List<AttendanceRecord> records = byDay.values.toList()
      ..sort((AttendanceRecord a, AttendanceRecord b) =>
          b.dateKey.compareTo(a.dateKey));
    return records;
  }
}
