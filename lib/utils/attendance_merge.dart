import '../models/attendance_record.dart';

/// Merges API history with locally created events.
/// Local events win for a given day because they hold the authoritative
/// pending/synced state of actions performed on this device.
class AttendanceMerge {
  AttendanceMerge._();

  static List<AttendanceRecord> combine(
    List<AttendanceRecord> remote,
    List<AttendanceRecord> local,
  ) {
    final Map<String, AttendanceRecord> merged = <String, AttendanceRecord>{};
    for (final AttendanceRecord record in remote) {
      merged[record.dateKey] = record;
    }
    for (final AttendanceRecord record in local) {
      if (record.checkIn != null || record.checkOut != null) {
        merged[record.dateKey] = record;
      }
    }
    final List<AttendanceRecord> result = merged.values.toList()
      ..sort((AttendanceRecord a, AttendanceRecord b) =>
          b.dateKey.compareTo(a.dateKey));
    return result;
  }
}
