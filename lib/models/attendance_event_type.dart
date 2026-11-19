enum AttendanceEventType { checkIn, checkOut }

extension AttendanceEventTypeX on AttendanceEventType {
  String get jsonValue => this == AttendanceEventType.checkIn
      ? 'check_in'
      : 'check_out';

  String get label => this == AttendanceEventType.checkIn
      ? 'Check-in'
      : 'Check-out';

  static AttendanceEventType fromJson(String value) =>
      value == 'check_out' ? AttendanceEventType.checkOut : AttendanceEventType.checkIn;
}

/// Kept for code that prefers a top-level helper over the extension.
AttendanceEventType attendanceEventTypeFromJson(String value) =>
    AttendanceEventTypeX.fromJson(value);

class AttendanceSubmissionResult {
  final String eventId;
  final String serverId;
  final bool duplicate;

  const AttendanceSubmissionResult({
    required this.eventId,
    required this.serverId,
    required this.duplicate,
  });

  factory AttendanceSubmissionResult.fromJson(Map<String, dynamic> json) {
    return AttendanceSubmissionResult(
      eventId: (json['eventId'] as String?) ?? '',
      serverId: (json['serverId'] as String?) ?? '',
      duplicate: (json['duplicate'] as bool?) ?? false,
    );
  }
}
