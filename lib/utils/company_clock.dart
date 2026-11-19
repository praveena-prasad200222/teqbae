import '../constants/app_config.dart';

/// All business dates are computed in the configured company timezone.
///
/// A fixed UTC offset is used instead of an IANA zone so the app has no
/// timezone-database dependency and tests stay deterministic. Replace this
/// class with a timezone-aware implementation for production.
class CompanyClock {
  final int offsetMinutes;
  final DateTime Function() utcNowProvider;

  CompanyClock({
    int? offsetMinutes,
    DateTime Function()? utcNowProvider,
  })  : offsetMinutes = offsetMinutes ?? AppConfig.companyTimezoneOffsetMinutes,
        utcNowProvider = utcNowProvider ?? (() => DateTime.now().toUtc());

  DateTime get utcNow => utcNowProvider().toUtc();

  DateTime get companyNow =>
      utcNow.add(Duration(minutes: offsetMinutes));

  DateTime toCompany(DateTime utc) =>
      utc.toUtc().add(Duration(minutes: offsetMinutes));

  DateTime fromCompany(DateTime companyLocal) =>
      companyLocal.subtract(Duration(minutes: offsetMinutes)).toUtc();

  String get todayKey => dateKey(utcNow);

  String get currentMonthKey => monthKey(utcNow);

  String dateKey(DateTime utc) => keyFromLocalDate(toCompany(utc));

  String monthKey(DateTime utc) {
    final DateTime local = toCompany(utc);
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}';
  }

  /// Builds a `YYYY-MM-DD` key from a date already expressed in company time.
  String keyFromLocalDate(DateTime companyLocal) =>
      '${companyLocal.year.toString().padLeft(4, '0')}-${companyLocal.month.toString().padLeft(2, '0')}-${companyLocal.day.toString().padLeft(2, '0')}';

  DateTime companyLocalDateFromKey(String key) {
    final List<String> parts = key.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// All calendar days count as leave days (weekends/holidays ignored).
  /// UTC construction avoids DST-related off-by-one errors.
  int daysInclusive(DateTime localStart, DateTime localEnd) {
    final DateTime start = DateTime.utc(
      localStart.year,
      localStart.month,
      localStart.day,
    );
    final DateTime end = DateTime.utc(
      localEnd.year,
      localEnd.month,
      localEnd.day,
    );
    return end.difference(start).inDays + 1;
  }
}
