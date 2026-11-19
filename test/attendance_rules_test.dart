import 'package:flutter_test/flutter_test.dart';

import 'package:teqbae/models/attendance_event.dart';
import 'package:teqbae/models/attendance_event_type.dart';
import 'package:teqbae/models/geo_point.dart';
import 'package:teqbae/models/office_location.dart';
import 'package:teqbae/utils/attendance_rules.dart';
import 'package:teqbae/utils/company_clock.dart';

CompanyClock _fixedClock() => CompanyClock(
      offsetMinutes: 330,
      utcNowProvider: () => DateTime.utc(2026, 1, 15, 4, 0),
    );

OfficeLocation _office({double radius = 200, bool configured = true}) =>
    OfficeLocation(
      name: 'Test Office',
      latitude: 10.000000,
      longitude: 76.000000,
      radiusMeters: radius,
      timezoneOffsetMinutes: 330,
      isConfigured: configured,
    );

GeoPoint _inside() =>
    const GeoPoint(latitude: 10.000000, longitude: 76.000000);

AttendanceEvent _event(AttendanceEventType type, int sequence) =>
    AttendanceEvent.create(
      type: type,
      timestampUtc: DateTime.utc(2026, 1, 15, 4, 0),
      latitude: 10.000000,
      longitude: 76.000000,
      dateKey: '2026-01-15',
      sequence: sequence,
    );

void main() {
  group('Attendance business rules', () {
    final AttendanceRules rules = AttendanceRules(clock: _fixedClock());

    test('check-out without check-in is rejected', () {
      final AttendanceDecision decision = rules.evaluate(
        events: <AttendanceEvent>[],
        type: AttendanceEventType.checkOut,
        position: _inside(),
        office: _office(),
      );

      expect(decision.allowed, isFalse);
      expect(
        decision.reason,
        AttendanceRejection.checkoutWithoutCheckin,
      );
    });

    test('repeated check-in on the same day is rejected', () {
      final List<AttendanceEvent> events = <AttendanceEvent>[
        _event(AttendanceEventType.checkIn, 1),
      ];

      final AttendanceDecision decision = rules.evaluate(
        events: events,
        type: AttendanceEventType.checkIn,
        position: _inside(),
        office: _office(),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reason, AttendanceRejection.alreadyCheckedIn);
    });

    test('check-out twice is rejected', () {
      final List<AttendanceEvent> events = <AttendanceEvent>[
        _event(AttendanceEventType.checkIn, 1),
        _event(AttendanceEventType.checkOut, 2),
      ];

      final AttendanceDecision decision = rules.evaluate(
        events: events,
        type: AttendanceEventType.checkOut,
        position: _inside(),
        office: _office(),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reason, AttendanceRejection.alreadyCheckedOut);
    });

    test('check-in outside the configured radius is rejected with distance',
        () {
      const GeoPoint far = GeoPoint(latitude: 10.0100, longitude: 76.000000);
      final AttendanceDecision decision = rules.evaluate(
        events: <AttendanceEvent>[],
        type: AttendanceEventType.checkIn,
        position: far,
        office: _office(),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reason, AttendanceRejection.outsideOffice);
      expect(decision.message, contains('200 m'));
    });

    test('radius is configurable', () {
      const GeoPoint mediumRange =
          GeoPoint(latitude: 10.0050, longitude: 76.000000);
      final AttendanceDecision decision = rules.evaluate(
        events: <AttendanceEvent>[],
        type: AttendanceEventType.checkIn,
        position: mediumRange,
        office: _office(radius: 600),
      );

      expect(decision.allowed, isTrue);
    });

    test('unconfigured office blocks attendance with a configuration message',
        () {
      final AttendanceDecision decision = rules.evaluate(
        events: <AttendanceEvent>[],
        type: AttendanceEventType.checkIn,
        position: _inside(),
        office: _office(configured: false),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reason, AttendanceRejection.officeNotConfigured);
      expect(decision.message, contains('Teqbae'));
      expect(decision.message, contains('OFFICE_LAT'));
      expect(decision.message, contains('OFFICE_LNG'));
    });

    test('company timezone controls the working-day key', () {
      final CompanyClock clock = CompanyClock(
        offsetMinutes: 330,
        utcNowProvider: () => DateTime.utc(2026, 1, 15, 18, 30),
      );
      // 18:30 UTC is 00:00 next day in UTC+05:30.
      expect(clock.todayKey, '2026-01-16');
    });
  });
}
