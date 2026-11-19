import 'dart:async';
import 'dart:math' as math;

import '../models/leave_balance.dart';
import '../models/leave_request.dart';
import '../models/leave_request_status.dart';
import '../models/leave_type.dart';
import '../models/sync_status.dart';
import '../services/api/api_client.dart';
import '../services/storage/local_storage.dart';

/// Leave requests are always saved locally first, then submitted. Requests
/// created offline (or when the API is unreachable) stay `Pending Sync` and are
/// sent by [SyncEngine] after reconnection using their stable client id.
class LeaveRepository {
  final ApiClient api;
  final LocalStorage storage;

  LeaveRepository({required this.api, required this.storage});

  Future<LeaveBalance?> getCachedBalance() => storage.getLeaveBalance();

  /// Cached value first; otherwise persist and show the documented demo sample
  /// so the UI never falls back to zeros while employee data is available.
  Future<LeaveBalance> getDisplayBalance() async {
    final LeaveBalance? cached = await getCachedBalance();
    if (cached != null) return cached;
    await storage.putLeaveBalance(LeaveBalance.sample);
    return LeaveBalance.sample;
  }

  Future<List<LeaveRequest>> getCachedRequests() => storage.getLeaveRequests();

  Future<LeaveBalance> fetchBalance() async {
    final LeaveBalance remote = await api.fetchLeaveBalance();
    final LeaveBalance? local = await getCachedBalance();
    // A locally deducted balance must never grow back because the in-memory
    // mock server restarted or a sync has not yet reflected the deduction.
    // Taking the lower value per leave type keeps both screens consistent while
    // still accepting a genuinely lower server balance.
    final LeaveBalance merged = local == null
        ? remote
        : LeaveBalance(
            casual: math.min(local.casual, remote.casual),
            sick: math.min(local.sick, remote.sick),
          );
    await storage.putLeaveBalance(merged);
    return merged;
  }

  /// Applies an idempotent local deduction/refund. Submission calls it once;
  /// the sync engine never touches the balance, so a re-sync cannot deduct the
  /// same request twice. Edits refund the old days and deduct the new days;
  /// deleting a Pending request refunds its days.
  Future<LeaveBalance> applyBalanceChange({
    required LeaveType oldType,
    required int oldDays,
    required LeaveType newType,
    required int newDays,
  }) async {
    final LeaveBalance current = await getDisplayBalance();
    int casual = current.casual;
    int sick = current.sick;
    if (oldDays > 0) {
      if (oldType == LeaveType.casual) {
        casual += oldDays;
      } else {
        sick += oldDays;
      }
    }
    if (newDays > 0) {
      if (newType == LeaveType.casual) {
        casual -= newDays;
      } else {
        sick -= newDays;
      }
    }
    final LeaveBalance updated = LeaveBalance(
      casual: casual < 0 ? 0 : casual,
      sick: sick < 0 ? 0 : sick,
    );
    await storage.putLeaveBalance(updated);
    return updated;
  }

  Future<List<LeaveRequest>> fetchRequests() async {
    final List<LeaveRequest> requests = await api.fetchLeaveRequests();
    // Do not drop locally queued requests when a remote snapshot arrives.
    final List<LeaveRequest> cached = await getCachedRequests();
    final Set<String> deleted =
        (await storage.getLeaveDeletionQueue()).toSet();

    // Preserve anything not yet accepted by the server: pending requests and
    // explicit 422 rejections both belong in the local history. A locally
    // edited request is Pending Sync and must win over the older remote copy
    // with the same id until the upsert reaches the server.
    final List<LeaveRequest> pending = cached
        .where((LeaveRequest r) =>
            r.syncStatus != SyncStatus.synced && !deleted.contains(r.id))
        .toList();
    final Set<String> pendingIds =
        pending.map((LeaveRequest r) => r.id).toSet();
    final List<LeaveRequest> merged = <LeaveRequest>[
      ...pending,
      ...requests.where((LeaveRequest r) =>
          !pendingIds.contains(r.id) && !deleted.contains(r.id)),
    ];
    await storage.putLeaveRequests(merged);
    return merged;
  }

  /// Creates and persists a request with a stable idempotency key. Called for
  /// both online and offline submissions so a failure can never be reported as
  /// a successful server submission.
  Future<LeaveRequest> queue({
    required LeaveType type,
    required String startDate,
    required String endDate,
    required String reason,
    required int days,
  }) async {
    final LeaveRequest pending = LeaveRequest.createPending(
      type: type,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      days: days,
    );
    final List<LeaveRequest> cached = await getCachedRequests();
    await storage.putLeaveRequests(<LeaveRequest>[pending, ...cached]);
    return pending;
  }

  /// Sends one queued request. On success the local pending copy is replaced
  /// by the server receipt, so a retry can never create a duplicate.
  Future<LeaveRequest> send(LeaveRequest pending) async {
    final LeaveRequest created = await api.submitLeaveRequest(
      type: pending.type,
      startDate: pending.startDate,
      endDate: pending.endDate,
      reason: pending.reason,
      days: pending.days,
      requestId: pending.id,
    );
    final LeaveRequest synced = created.copyWith(
      syncStatus: SyncStatus.synced,
      attempts: 0,
      lastError: null,
    );
    final List<LeaveRequest> cached = await getCachedRequests();
    final List<LeaveRequest> updated = <LeaveRequest>[
      synced,
      ...cached.where((LeaveRequest r) => r.id != pending.id),
    ];
    await storage.putLeaveRequests(updated);
    return synced;
  }

  Future<void> updatePending(
    LeaveRequest request, {
    SyncStatus? syncStatus,
    int? attempts,
    String? lastError,
  }) async {
    final List<LeaveRequest> cached = await getCachedRequests();
    final List<LeaveRequest> updated = cached
        .map(
          (LeaveRequest r) => r.id == request.id
              ? r.copyWith(
                  syncStatus: syncStatus,
                  attempts: attempts,
                  lastError: lastError,
                )
              : r,
        )
        .toList();
    await storage.putLeaveRequests(updated);
  }

  /// Replaces an existing request in place. The id and submitted timestamp are
  /// preserved, so the next sync is an update/upsert rather than a second
  /// request. Marking it Pending Sync makes the sync engine send the latest
  /// version after an edit made offline.
  Future<LeaveRequest> updateRequest({
    required String requestId,
    required LeaveType type,
    required String startDate,
    required String endDate,
    required String reason,
    required int days,
  }) async {
    final List<LeaveRequest> cached = await getCachedRequests();
    final int index =
        cached.indexWhere((LeaveRequest r) => r.id == requestId);
    if (index < 0) {
      throw StateError('Leave request not found.');
    }
    final LeaveRequest original = cached[index];
    if (original.status != LeaveRequestStatus.pending ||
        original.syncStatus == SyncStatus.rejected) {
      throw StateError(
        'Only Pending, non-rejected leave requests can be edited.',
      );
    }
    final LeaveRequest updated = cached[index].copyWith(
      type: type,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      days: days,
      syncStatus: SyncStatus.pending,
      attempts: 0,
      lastError: null,
    );
    final List<LeaveRequest> next = List<LeaveRequest>.from(cached);
    next[index] = updated;
    await storage.putLeaveRequests(next);
    return updated;
  }

  /// Removes the record locally and remembers its id until the API confirms
  /// deletion. The deletion queue is filtered out of remote fetches, so the
  /// entry cannot reappear before the server catches up.
  Future<void> delete(String id) async {
    final List<LeaveRequest> cached = await getCachedRequests();
    LeaveRequest? target;
    for (final LeaveRequest request in cached) {
      if (request.id == id) {
        target = request;
        break;
      }
    }
    if (target == null) {
      throw StateError('Leave request not found.');
    }
    if (target.status != LeaveRequestStatus.pending ||
        target.syncStatus == SyncStatus.rejected) {
      throw StateError(
        'Only Pending, non-rejected leave requests can be deleted.',
      );
    }
    await storage.putLeaveRequests(
      cached.where((LeaveRequest r) => r.id != id).toList(),
    );
    final List<String> queue = await storage.getLeaveDeletionQueue();
    if (!queue.contains(id)) {
      await storage.putLeaveDeletionQueue(<String>[...queue, id]);
    }
  }

  /// Approves a Pending request locally and marks it as approved/synced.
  Future<LeaveRequest> approveRequest(String requestId) async {
    final List<LeaveRequest> cached = await getCachedRequests();
    final int index = cached.indexWhere((LeaveRequest r) => r.id == requestId);
    if (index < 0) {
      throw StateError('Leave request not found.');
    }
    final LeaveRequest updated = cached[index].copyWith(
      status: LeaveRequestStatus.approved,
      syncStatus: SyncStatus.synced,
      clearLastError: true,
      attempts: 0,
    );
    final List<LeaveRequest> next = List<LeaveRequest>.from(cached);
    next[index] = updated;
    await storage.putLeaveRequests(next);
    unawaited(api.approveLeaveRequest(requestId).catchError((_) {}));
    return updated;
  }

  Future<void> remove(String id) => delete(id);
}
