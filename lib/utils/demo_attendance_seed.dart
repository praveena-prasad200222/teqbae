import '../constants/app_config.dart';
import '../models/attendance_event.dart';
import '../models/attendance_record.dart';

/// Deterministic sample history used by the mock API and by a fresh local
/// cache. It is clearly demo data: no office coordinates are bundled and these
/// records are never treated as attendance actions performed on the device.
class DemoAttendanceSeed {
  DemoAttendanceSeed._();

  static List<Map<String, dynamic>> eventJson({
    DateTime? nowUtc,
    int? offsetMinutes,
  }) {
    final int offset = offsetMinutes ?? AppConfig.companyTimezoneOffsetMinutes;
    final DateTime companyNow =
        (nowUtc ?? DateTime.now().toUtc()).add(Duration(minutes: offset));
    final DateTime companyMidnight =
        DateTime(companyNow.year, companyNow.month, companyNow.day);

    final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
    int sequence = 1;
    for (int dayOffset = 1; dayOffset <= 5; dayOffset++) {
      final DateTime day =
          companyMidnight.subtract(Duration(days: dayOffset));
      final String key = _dateKey(day);
      final DateTime checkInUtc = DateTime(
        day.year,
        day.month,
        day.day,
        9,
        15,
      ).subtract(Duration(minutes: offset));
      final DateTime checkOutUtc = DateTime(
        day.year,
        day.month,
        day.day,
        18,
        30,
      ).subtract(Duration(minutes: offset));

      events.add(_event(
        eventId: 'seed-in-$key',
        type: 'check_in',
        dateKey: key,
        timestampUtc: checkInUtc,
        sequence: sequence++,
      ));
      events.add(_event(
        eventId: 'seed-out-$key',
        type: 'check_out',
        dateKey: key,
        timestampUtc: checkOutUtc,
        sequence: sequence++,
      ));
    }
    return events;
  }

  static List<AttendanceRecord> records({
    DateTime? nowUtc,
    int? offsetMinutes,
  }) =>
      AttendanceRecord.build(
        eventJson(nowUtc: nowUtc, offsetMinutes: offsetMinutes)
            .map((Map<String, dynamic> json) => AttendanceEvent.fromJson(json))
            .toList(),
      );

  static Map<String, dynamic> _event({
    required String eventId,
    required String type,
    required String dateKey,
    required DateTime timestampUtc,
    required int sequence,
  }) =>
      <String, dynamic>{
        'eventId': eventId,
        'employeeId': AppConfig.employeeId,
        'type': type,
        'timestampUtc': timestampUtc.toUtc().toIso8601String(),
        'latitude': 0.0,
        'longitude': 0.0,
        'dateKey': dateKey,
        'syncStatus': 'synced',
        'sequence': sequence,
        'attempts': 0,
      };

  static String _dateKey(DateTime companyLocal) =>
      '${companyLocal.year.toString().padLeft(4, '0')}-'
      '${companyLocal.month.toString().padLeft(2, '0')}-'
      '${companyLocal.day.toString().padLeft(2, '0')}';
}
