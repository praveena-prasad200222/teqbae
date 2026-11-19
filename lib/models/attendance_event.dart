import 'package:uuid/uuid.dart';

import '../constants/app_config.dart';
import 'attendance_event_type.dart';
import 'sync_status.dart';

/// A single immutable attendance event.
///
/// [eventId] is generated once on the device and never changes. It is the
/// idempotency key used for every retry, which is what prevents duplicate
/// server records after a timeout. [sequence] preserves the order in which
/// events were created locally.
class AttendanceEvent {
  final String eventId;
  final String employeeId;
  final AttendanceEventType type;
  final DateTime timestampUtc;
  final double latitude;
  final double longitude;
  final String dateKey;
  final SyncStatus syncStatus;
  final int sequence;
  final int attempts;
  final String? lastError;
  final String? serverEventId;

  const AttendanceEvent({
    required this.eventId,
    required this.employeeId,
    required this.type,
    required this.timestampUtc,
    required this.latitude,
    required this.longitude,
    required this.dateKey,
    required this.syncStatus,
    required this.sequence,
    required this.attempts,
    this.lastError,
    this.serverEventId,
  });

  /// Creates a brand new, pending event with a fresh idempotency key.
  factory AttendanceEvent.create({
    required AttendanceEventType type,
    required DateTime timestampUtc,
    required double latitude,
    required double longitude,
    required String dateKey,
    required int sequence,
    String? employeeId,
  }) {
    return AttendanceEvent(
      eventId: const Uuid().v4(),
      employeeId: employeeId ?? AppConfig.employeeId,
      type: type,
      timestampUtc: timestampUtc.toUtc(),
      latitude: latitude,
      longitude: longitude,
      dateKey: dateKey,
      syncStatus: SyncStatus.pending,
      sequence: sequence,
      attempts: 0,
    );
  }

  factory AttendanceEvent.fromJson(Map<String, dynamic> json) {
    return AttendanceEvent(
      eventId: json['eventId'] as String,
      employeeId: (json['employeeId'] as String?) ?? AppConfig.employeeId,
      type: AttendanceEventTypeX.fromJson(
          (json['type'] as String?) ?? 'check_in'),
      timestampUtc: DateTime.parse(json['timestampUtc'] as String).toUtc(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      dateKey: json['dateKey'] as String,
      syncStatus:
          SyncStatusX.fromJson((json['syncStatus'] as String?) ?? 'pending'),
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
      serverEventId: json['serverEventId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'eventId': eventId,
        'employeeId': employeeId,
        'type': type.jsonValue,
        'timestampUtc': timestampUtc.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'dateKey': dateKey,
        'syncStatus': syncStatus.jsonValue,
        'sequence': sequence,
        'attempts': attempts,
        'lastError': lastError,
        'serverEventId': serverEventId,
      };

  AttendanceEvent copyWith({
    SyncStatus? syncStatus,
    int? attempts,
    String? lastError,
    String? serverEventId,
  }) {
    return AttendanceEvent(
      eventId: eventId,
      employeeId: employeeId,
      type: type,
      timestampUtc: timestampUtc,
      latitude: latitude,
      longitude: longitude,
      dateKey: dateKey,
      syncStatus: syncStatus ?? this.syncStatus,
      sequence: sequence,
      attempts: attempts ?? this.attempts,
      lastError: lastError,
      serverEventId: serverEventId ?? this.serverEventId,
    );
  }

  @override
  String toString() =>
      'AttendanceEvent($eventId, ${type.jsonValue}, $dateKey, ${syncStatus.label})';
}
