import 'package:flutter_test/flutter_test.dart';

import 'package:teqbae/models/leave_balance.dart';
import 'package:teqbae/models/leave_request.dart';
import 'package:teqbae/models/leave_request_status.dart';
import 'package:teqbae/models/leave_type.dart';
import 'package:teqbae/utils/company_clock.dart';
import 'package:teqbae/utils/leave_rules.dart';

final CompanyClock _clock = CompanyClock(
  offsetMinutes: 330,
  utcNowProvider: () => DateTime.utc(2026, 1, 15, 4, 0),
);

const LeaveBalance _balance = LeaveBalance(casual: 2, sick: 5);

List<LeaveRequest> _existing() => <LeaveRequest>[
      LeaveRequest(
        id: 'R1',
        type: LeaveType.casual,
        startDate: '2026-01-20',
        endDate: '2026-01-21',
        reason: 'Already approved event.',
        days: 2,
        status: LeaveRequestStatus.pending,
        submittedAtUtc: DateTime.utc(2026, 1, 10),
      ),
      LeaveRequest(
        id: 'R2',
        type: LeaveType.sick,
        startDate: '2026-01-25',
        endDate: '2026-01-26',
        reason: 'Approved medical leave.',
        days: 2,
        status: LeaveRequestStatus.approved,
        submittedAtUtc: DateTime.utc(2026, 1, 10),
      ),
      LeaveRequest(
        id: 'R3',
        type: LeaveType.casual,
        startDate: '2026-01-22',
        endDate: '2026-01-23',
        reason: 'Rejected request should not block.',
        days: 2,
        status: LeaveRequestStatus.rejected,
        submittedAtUtc: DateTime.utc(2026, 1, 10),
      ),
    ];

LeaveValidationResult validate({
  DateTime? start,
  DateTime? end,
  String reason = 'Family function at home.',
  LeaveType type = LeaveType.casual,
}) {
  return LeaveRules(clock: _clock).validate(
    type: type,
    startDate: start ?? DateTime(2026, 1, 17),
    endDate: end ?? DateTime(2026, 1, 18),
    reason: reason,
    balance: _balance,
    existingRequests: _existing(),
  );
}

void main() {
  group('Leave validation rules', () {
    test('valid request passes', () {
      expect(validate().isValid, isTrue);
    });

    test('start date before current company date is rejected', () {
      final result = validate(start: DateTime(2026, 1, 14));
      expect(result.isValid, isFalse);
      expect(result.errors.join(), contains('Start date cannot be before'));
    });

    test('end date before the current company date is rejected', () {
      final result = validate(
        start: DateTime(2026, 1, 17),
        end: DateTime(2026, 1, 14),
      );
      expect(result.isValid, isFalse);
      expect(result.errors.join(), contains('End date cannot be before the current company date'));
    });

    test('end date before start date is rejected', () {
      final result = validate(end: DateTime(2026, 1, 16));
      expect(result.isValid, isFalse);
      expect(result.errors.join(), contains('End date cannot be before the start date'));
    });

    test('reason requires 10 non-whitespace characters', () {
      final result = validate(reason: 'short   ');
      expect(result.isValid, isFalse);
      expect(result.errors.join(), contains('10 non-whitespace'));
    });

    test('requested days cannot exceed balance', () {
      final result = validate(
        start: DateTime(2026, 1, 17),
        end: DateTime(2026, 1, 19),
      );
      expect(result.isValid, isFalse);
      expect(result.errors.join(), contains('exceed the available'));
    });

    test('dates overlapping pending or approved requests are rejected', () {
      final pendingOverlap = validate(
        start: DateTime(2026, 1, 21),
        end: DateTime(2026, 1, 22),
      );
      final approvedOverlap = validate(
        start: DateTime(2026, 1, 26),
        end: DateTime(2026, 1, 27),
        type: LeaveType.sick,
      );
      expect(pendingOverlap.isValid, isFalse);
      expect(pendingOverlap.errors.join(), contains('overlap'));
      expect(approvedOverlap.isValid, isFalse);
      expect(approvedOverlap.errors.join(), contains('overlap'));
    });

    test('rejected requests do not block a new application', () {
      final result = validate(
        start: DateTime(2026, 1, 22),
        end: DateTime(2026, 1, 23),
      );
      expect(result.isValid, isTrue);
    });

    test('all calendar days count (weekends included)', () {
      expect(
        _clock.daysInclusive(DateTime(2026, 1, 16), DateTime(2026, 1, 19)),
        4,
      );
    });
  });
}
