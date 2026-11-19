import 'package:uuid/uuid.dart';

import '../constants/app_config.dart';
import 'leave_request_status.dart';
import 'leave_type.dart';
import 'sync_status.dart';

class LeaveRequest {
  final String id;
  final LeaveType type;
  final String startDate;
  final String endDate;
  final String reason;
  final int days;
  final LeaveRequestStatus status;
  final DateTime submittedAtUtc;

  /// Sync state of this local record. Server responses are always `synced`;
  /// requests created while offline (or when the API is unreachable) stay
  /// `pending` until the SyncEngine receives a receipt.
  final SyncStatus syncStatus;
  final int attempts;
  final String? lastError;

  const LeaveRequest({
    required this.id,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.days,
    required this.status,
    required this.submittedAtUtc,
    this.syncStatus = SyncStatus.synced,
    this.attempts = 0,
    this.lastError,
  });

  /// Creates a locally queued request. [id] is generated once and reused as the
  /// idempotency key on every sync attempt, so reconnection cannot duplicate it.
  factory LeaveRequest.createPending({
    required LeaveType type,
    required String startDate,
    required String endDate,
    required String reason,
    required int days,
    DateTime? submittedAtUtc,
  }) {
    return LeaveRequest(
      id: 'LRV-LOCAL-${const Uuid().v4()}',
      type: type,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      days: days,
      status: LeaveRequestStatus.pending,
      submittedAtUtc: submittedAtUtc?.toUtc() ?? DateTime.now().toUtc(),
      syncStatus: SyncStatus.pending,
      attempts: 0,
    );
  }

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    return LeaveRequest(
      id: (json['id'] as String?) ?? '',
      type: LeaveTypeX.fromJson((json['type'] as String?) ?? 'casual'),
      startDate: (json['startDate'] as String?) ?? '',
      endDate: (json['endDate'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? '',
      days: (json['days'] as num?)?.toInt() ?? 0,
      status: LeaveRequestStatusX.fromJson(
          (json['status'] as String?) ?? 'pending'),
      submittedAtUtc: json['submittedAtUtc'] != null
          ? DateTime.parse(json['submittedAtUtc'] as String).toUtc()
          : DateTime.now().toUtc(),
      syncStatus:
          SyncStatusX.fromJson((json['syncStatus'] as String?) ?? 'synced'),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'employeeId': AppConfig.employeeId,
        'type': type.jsonValue,
        'startDate': startDate,
        'endDate': endDate,
        'reason': reason,
        'days': days,
        'status': status.jsonValue,
        'submittedAtUtc': submittedAtUtc.toIso8601String(),
        'syncStatus': syncStatus.jsonValue,
        'attempts': attempts,
        'lastError': lastError,
      };

  LeaveRequest copyWith({
    LeaveRequestStatus? status,
    SyncStatus? syncStatus,
    int? attempts,
    String? lastError,
  }) {
    return LeaveRequest(
      id: id,
      type: type,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      days: days,
      status: status ?? this.status,
      submittedAtUtc: submittedAtUtc,
      syncStatus: syncStatus ?? this.syncStatus,
      attempts: attempts ?? this.attempts,
      lastError: lastError,
    );
  }
}
