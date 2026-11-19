import '../models/attendance_event.dart';
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
      final AttendanceRecord? existing = merged[record.dateKey];
      if (existing == null) {
        if (record.checkIn != null || record.checkOut != null) {
          merged[record.dateKey] = record;
        }
      } else {
        // Merge checkIn and checkOut so neither is lost.
        // Local events take precedence over remote events if both exist.
        final AttendanceEvent? checkIn = record.checkIn ?? existing.checkIn;
        final AttendanceEvent? checkOut = record.checkOut ?? existing.checkOut;
        merged[record.dateKey] = AttendanceRecord(
          dateKey: record.dateKey,
          checkIn: checkIn,
          checkOut: checkOut,
        );
      }
    }
    final List<AttendanceRecord> result = merged.values.toList()
      ..sort((AttendanceRecord a, AttendanceRecord b) =>
          b.dateKey.compareTo(a.dateKey));
    return result;
  }
}
