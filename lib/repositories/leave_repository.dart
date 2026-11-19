import '../models/leave_balance.dart';
import '../models/leave_request.dart';
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
    final LeaveBalance balance = await api.fetchLeaveBalance();
    await storage.putLeaveBalance(balance);
    return balance;
  }

  Future<List<LeaveRequest>> fetchRequests() async {
    final List<LeaveRequest> requests = await api.fetchLeaveRequests();
    // Do not drop locally queued requests when a remote snapshot arrives.
    final List<LeaveRequest> cached = await getCachedRequests();
    // Preserve anything not yet accepted by the server: pending requests and
    // explicit 422 rejections both belong in the local history.
    final List<LeaveRequest> pending = cached
        .where((LeaveRequest r) => r.syncStatus != SyncStatus.synced)
        .toList();
    final Set<String> remoteIds =
        requests.map((LeaveRequest r) => r.id).toSet();
    final List<LeaveRequest> merged = <LeaveRequest>[
      ...pending.where((LeaveRequest r) => !remoteIds.contains(r.id)),
      ...requests,
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

  Future<void> remove(String id) async {
    final List<LeaveRequest> cached = await getCachedRequests();
    await storage.putLeaveRequests(
      cached.where((LeaveRequest r) => r.id != id).toList(),
    );
  }
}
