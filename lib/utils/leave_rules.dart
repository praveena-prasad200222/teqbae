import '../models/leave_balance.dart';
import '../models/leave_request.dart';
import '../models/leave_request_status.dart';
import '../models/leave_type.dart';
import 'company_clock.dart';

class LeaveValidationResult {
  final List<String> errors;

  const LeaveValidationResult(this.errors);

  bool get isValid => errors.isEmpty;

  String? get firstError => errors.isEmpty ? null : errors.first;
}

/// Pure leave validation used by the ViewModel. The server repeats all of it.
class LeaveRules {
  final CompanyClock clock;

  const LeaveRules({required this.clock});

  /// Calendar restrictions only. The ViewModel exposes this so the screen can
  /// show the same message before attempting a submission.
  LeaveValidationResult validateDates({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final List<String> errors = <String>[];
    final String startKey = clock.keyFromLocalDate(startDate);
    final String endKey = clock.keyFromLocalDate(endDate);
    final String todayKey = clock.todayKey;

    if (startKey.compareTo(todayKey) < 0) {
      errors.add('Start date cannot be before the current company date ($todayKey).');
    }
    if (endKey.compareTo(todayKey) < 0) {
      errors.add('End date cannot be before the current company date ($todayKey).');
    }
    if (endKey.compareTo(startKey) < 0) {
      errors.add('End date cannot be before the start date.');
    }

    return LeaveValidationResult(errors);
  }

  LeaveValidationResult validate({
    required LeaveType type,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    required LeaveBalance balance,
    required List<LeaveRequest> existingRequests,
  }) {
    final LeaveValidationResult dateValidation = validateDates(
      startDate: startDate,
      endDate: endDate,
    );
    final List<String> errors = <String>[...dateValidation.errors];

    final int nonWhitespaceLength =
        reason.replaceAll(RegExp(r'\s'), '').length;
    if (nonWhitespaceLength < 10) {
      errors.add('Reason must contain at least 10 non-whitespace characters.');
    }

    final int requestedDays = clock.daysInclusive(startDate, endDate);
    final String startKey = clock.keyFromLocalDate(startDate);
    final String endKey = clock.keyFromLocalDate(endDate);
    if (endKey.compareTo(startKey) >= 0 &&
        requestedDays > balance.forType(type)) {
      errors.add(
        'Requested $requestedDays day(s) exceed the available ${type.label} balance of ${balance.forType(type)}.',
      );
    }

    for (final LeaveRequest request in existingRequests) {
      if (request.status == LeaveRequestStatus.rejected) continue;
      final bool overlaps = startKey.compareTo(request.endDate) <= 0 &&
          endKey.compareTo(request.startDate) >= 0;
      if (overlaps) {
        errors.add(
          'Dates overlap an existing ${request.status.label.toLowerCase()} leave request (${request.startDate} - ${request.endDate}).',
        );
        break;
      }
    }

    return LeaveValidationResult(errors);
  }
}
