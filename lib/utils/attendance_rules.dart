import '../constants/app_config.dart';
import '../models/attendance_event.dart';
import '../models/attendance_event_type.dart';
import '../models/attendance_record.dart';
import '../models/attendance_status.dart';
import '../models/geo_point.dart';
import '../models/office_location.dart';
import 'company_clock.dart';
import 'geofence.dart';

enum AttendanceRejection {
  alreadyCheckedIn,
  checkoutWithoutCheckin,
  alreadyCheckedOut,
  outsideOffice,
  invalidPosition,
  officeNotConfigured,
}

class AttendanceDecision {
  final bool allowed;
  final AttendanceRejection? reason;
  final String? message;

  const AttendanceDecision._(this.allowed, this.reason, this.message);

  factory AttendanceDecision.allowed() =>
      const AttendanceDecision._(true, null, null);

  factory AttendanceDecision.rejected(
          AttendanceRejection reason, String message) =>
      AttendanceDecision._(false, reason, message);
}

class AttendanceDayState {
  final String dateKey;
  final AttendanceEvent? checkIn;
  final AttendanceEvent? checkOut;

  const AttendanceDayState({
    required this.dateKey,
    required this.checkIn,
    required this.checkOut,
  });

  AttendanceStatus get status {
    if (checkOut != null) return AttendanceStatus.checkedOut;
    if (checkIn != null) return AttendanceStatus.checkedIn;
    return AttendanceStatus.notCheckedIn;
  }
}

/// Pure, synchronously testable attendance rules. No Flutter or platform code.
class AttendanceRules {
  final CompanyClock clock;

  const AttendanceRules({required this.clock});

  AttendanceDayState dayState(List<AttendanceEvent> events, {String? dateKey}) {
    final String key = dateKey ?? clock.todayKey;
    final List<AttendanceRecord> records = AttendanceRecord.build(
      events.where((AttendanceEvent e) => e.dateKey == key).toList(),
    );
    final AttendanceRecord record = records.isEmpty
        ? AttendanceRecord(dateKey: key, checkIn: null, checkOut: null)
        : records.first;
    return AttendanceDayState(
      dateKey: key,
      checkIn: record.checkIn,
      checkOut: record.checkOut,
    );
  }

  /// Validates business rules AND the geofence before an event is created.
  AttendanceDecision evaluate({
    required List<AttendanceEvent> events,
    required AttendanceEventType type,
    required GeoPoint? position,
    required OfficeLocation office,
    String? dateKey,
  }) {
    final AttendanceDayState day = dayState(events, dateKey: dateKey);

    if (type == AttendanceEventType.checkIn && day.checkIn != null) {
      return AttendanceDecision.rejected(
        AttendanceRejection.alreadyCheckedIn,
        'You have already checked in today. Only one check-in per working day is allowed.',
      );
    }

    if (type == AttendanceEventType.checkOut) {
      if (day.checkIn == null) {
        return AttendanceDecision.rejected(
          AttendanceRejection.checkoutWithoutCheckin,
          'Check-out is not allowed without a successful check-in.',
        );
      }
      if (day.checkOut != null) {
        return AttendanceDecision.rejected(
          AttendanceRejection.alreadyCheckedOut,
          'You have already checked out today. Only one session per day is allowed.',
        );
      }
    }

    if (position == null) {
      return AttendanceDecision.rejected(
        AttendanceRejection.invalidPosition,
        'Current GPS location is unavailable. Please try again.',
      );
    }

    if (!office.isConfigured) {
      return AttendanceDecision.rejected(
        AttendanceRejection.officeNotConfigured,
        'Teqbae office coordinates are not configured. Attendance is blocked '
        'until the real office latitude and longitude are supplied. '
        '${AppConfig.officeConfigurationHint}',
      );
    }

    if (!GeoFence.isWithin(current: position, office: office)) {
      final double distance = GeoFence.distanceMeters(
        GeoPoint(latitude: office.latitude, longitude: office.longitude),
        position,
      );
      return AttendanceDecision.rejected(
        AttendanceRejection.outsideOffice,
        'You are ${distance.round()} m from ${office.name}. Attendance is only allowed within ${office.radiusMeters.round()} m of the office.',
      );
    }

    return AttendanceDecision.allowed();
  }
}
