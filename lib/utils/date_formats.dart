import '../models/attendance_event.dart';
import '../models/attendance_record.dart';
import 'company_clock.dart';

class DateFormats {
  DateFormats._();

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// Formats an event timestamp in the configured company timezone.
  static String time(DateTime utc, CompanyClock clock) {
    final DateTime local = clock.toCompany(utc);
    return '${_two(local.hour)}:${_two(local.minute)}';
  }

  static String dayMonth(String dateKey) {
    final List<String> parts = dateKey.split('-');
    if (parts.length != 3) return dateKey;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  static String weekday(String dateKey) {
    final List<String> parts = dateKey.split('-');
    if (parts.length != 3) return '';
    final DateTime date = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    const List<String> names = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    return names[date.weekday - 1];
  }

  static String duration(Duration? value) {
    if (value == null) return '--:--';
    final int hours = value.inHours;
    final int minutes = value.inMinutes.remainder(60);
    return '${_two(hours)}h ${_two(minutes)}m';
  }

  static String eventTime(AttendanceEvent? event, CompanyClock clock) =>
      event == null ? '--:--' : time(event.timestampUtc, clock);

  static String recordTime(AttendanceRecord record, CompanyClock clock,
          {required bool checkIn}) =>
      checkIn
          ? eventTime(record.checkIn, clock)
          : eventTime(record.checkOut, clock);
}
