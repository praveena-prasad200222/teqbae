import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/action_result.dart';
import '../models/leave_balance.dart';
import '../models/leave_request.dart';
import '../models/leave_request_status.dart';
import '../models/leave_type.dart';
import '../models/sync_status.dart';
import '../repositories/leave_repository.dart';
import '../utils/company_clock.dart';
import '../utils/leave_rules.dart';
import 'connectivity_viewmodel.dart';
import 'sync_viewmodel.dart';
import 'view_state.dart';

class LeaveViewModel extends ChangeNotifier {
  final LeaveRepository repository;
  final ConnectivityViewModel connectivity;
  final CompanyClock clock;
  final SyncViewModel? sync;

  /// Lets the composition root refresh the Dashboard's separate balance value
  /// after a leave is added, edited or deleted.
  final Future<void> Function()? onBalanceChanged;

  LeaveViewModel({
    required this.repository,
    required this.connectivity,
    required this.clock,
    this.sync,
    this.onBalanceChanged,
  }) {
    connectivity.addListener(_onConnectivityChanged);
  }

  ViewState _state = ViewState.initial;
  String? _errorMessage;
  String? _refreshError;
  LeaveBalance? _balance;
  List<LeaveRequest> _requests = <LeaveRequest>[];
  bool _isSubmitting = false;
  bool _isRefreshing = false;
  Future<void>? _refreshFuture;

  ViewState get state => _state;
  String? get errorMessage => _errorMessage;
  String? get refreshError => _refreshError;
  LeaveBalance? get balance => _balance;
  List<LeaveRequest> get requests =>
      List<LeaveRequest>.unmodifiable(_requests);
  bool get isSubmitting => _isSubmitting;
  bool get isRefreshing => _isRefreshing;
  bool get isOffline => connectivity.isOffline;
  bool get canSubmit => true;

  int get pendingSyncCount => _requests
      .where((LeaveRequest r) =>
          r.status != LeaveRequestStatus.approved &&
          (r.syncStatus == SyncStatus.pending ||
              r.syncStatus == SyncStatus.failed))
      .length;

  /// Date-only validation shared with the screen before submission.
  String? validateDates({
    required DateTime startDate,
    required DateTime endDate,
  }) =>
      LeaveRules(clock: clock)
          .validateDates(startDate: startDate, endDate: endDate)
          .firstError;

  /// First load: cached/sample balance and cached requests appear immediately.
  Future<void> load() => _beginRefresh();

  Future<void> refresh() => _beginRefresh();

  /// Re-reads cached requests and balance after a sync attempt or local change.
  Future<void> reloadLocal() async {
    try {
      _requests = await repository.getCachedRequests();
      _balance = await repository.getCachedBalance() ?? _balance;
      if (_state == ViewState.initial || _state == ViewState.loading) {
        _state = ViewState.ready;
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Leave local reload failed: $error');
    }
  }

  Future<void> _beginRefresh() {
    final Future<void>? pending = _refreshFuture;
    if (pending != null) return pending;

    final Completer<void> completer = Completer<void>();
    _refreshFuture = completer.future;
    unawaited(_loadCacheThenRefresh(completer));
    return completer.future;
  }

  Future<void> _loadCacheThenRefresh(Completer<void> completer) async {
    _refreshError = null;
    try {
      _balance ??= await repository.getDisplayBalance();
      if (_requests.isEmpty) {
        _requests = await repository.getCachedRequests();
      }
      _state = ViewState.ready;
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString();
      _state = ViewState.error;
      _finish(completer);
      return;
    }

    if (connectivity.isOffline) {
      _refreshError = 'Offline — showing locally saved leave information.';
      _finish(completer);
      return;
    }

    final List<Object> errors = await _fetchRemote();
    if (errors.isNotEmpty) {
      _refreshError =
          '${errors.first} Showing locally saved data. You can retry below.';
    } else {
      _refreshError = null;
    }
    _finish(completer);
  }

  Future<List<Object>> _fetchRemote() async {
    _isRefreshing = true;
    notifyListeners();

    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _attempt(() async {
        _balance = await repository.fetchBalance();
      }),
      _attempt(() async {
        _requests = await repository.fetchRequests();
      }),
    ]);
    return results.whereType<Object>().toList();
  }

  Future<Object?> _attempt(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } catch (error) {
      return error;
    }
  }

  void _finish(Completer<void> completer) {
    _isRefreshing = false;
    if (identical(_refreshFuture, completer.future)) _refreshFuture = null;
    if (!completer.isCompleted) completer.complete();
    notifyListeners();
  }

  Future<ActionResult> submit({
    required LeaveType type,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    final String? dateError =
        validateDates(startDate: startDate, endDate: endDate);
    if (dateError != null) return ActionResult.fail(dateError);

    final LeaveBalance balance = _balance ?? LeaveBalance.sample;
    final LeaveValidationResult validation = LeaveRules(clock: clock).validate(
      type: type,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      balance: balance,
      existingRequests: _requests,
    );
    if (!validation.isValid) {
      return ActionResult.fail(validation.errors.join(' '));
    }

    _isSubmitting = true;
    notifyListeners();

    try {
      final String start = clock.keyFromLocalDate(startDate);
      final String end = clock.keyFromLocalDate(endDate);
      final int days = clock.daysInclusive(startDate, endDate);

      // Always persist first. Offline submissions and API failures therefore
      // become real Pending Sync records, never a false success.
      await repository.queue(
        type: type,
        startDate: start,
        endDate: end,
        reason: reason.trim(),
        days: days,
      );
      // Deduct exactly once, at local submission time. The sync engine only
      // uploads the request, so re-syncing the same id cannot deduct again.
      _balance = await repository.applyBalanceChange(
        oldType: type,
        oldDays: 0,
        newType: type,
        newDays: days,
      );
      _requests = await repository.getCachedRequests();
      await onBalanceChanged?.call();
      await sync?.refresh();
      notifyListeners();

      // Foreground submission is deliberately local-only. A slow or broken API
      // must never block the employee from filing leave. The sync engine owns
      // all network attempts and reports validation/server errors on the card.
      unawaited(_syncInBackground());
      return ActionResult.ok(
        connectivity.isOffline
            ? 'Leave added successfully! Saved as Pending Sync and will be '
                'submitted when the connection returns.'
            : 'Leave added successfully! Status: Pending Sync.',
      );
    } catch (error) {
      return ActionResult.fail('Unable to save leave request: $error');
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Updates an existing Pending request in place. The stable id is preserved,
  /// so the next sync is an upsert and cannot create a second request.
  Future<ActionResult> updateRequest({
    required String requestId,
    required LeaveType type,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    final LeaveRequest? existing = _findRequest(requestId);
    if (existing == null) {
      return ActionResult.fail('Leave request not found.');
    }
    if (existing.status != LeaveRequestStatus.pending ||
        existing.syncStatus == SyncStatus.rejected) {
      return ActionResult.fail(
        'Only Pending, non-rejected leave requests can be edited.',
      );
    }

    final String? dateError =
        validateDates(startDate: startDate, endDate: endDate);
    if (dateError != null) return ActionResult.fail(dateError);

    final LeaveBalance balance = _balance ?? LeaveBalance.sample;
    // The current balance already reflects this request's original days. Add
    // them back for the validation so an edit is not rejected against itself.
    final LeaveBalance validationBalance = existing.type == type
        ? (type == LeaveType.casual
            ? LeaveBalance(
                casual: balance.casual + existing.days,
                sick: balance.sick,
              )
            : LeaveBalance(
                casual: balance.casual,
                sick: balance.sick + existing.days,
              ))
        : balance;
    final LeaveValidationResult validation = LeaveRules(clock: clock).validate(
      type: type,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      balance: validationBalance,
      // Exclude the request being edited, otherwise it would overlap itself.
      existingRequests:
          _requests.where((LeaveRequest r) => r.id != requestId).toList(),
    );
    if (!validation.isValid) {
      return ActionResult.fail(validation.errors.join(' '));
    }

    _isSubmitting = true;
    notifyListeners();
    try {
      final int newDays = clock.daysInclusive(startDate, endDate);
      await repository.updateRequest(
        requestId: requestId,
        type: type,
        startDate: clock.keyFromLocalDate(startDate),
        endDate: clock.keyFromLocalDate(endDate),
        reason: reason.trim(),
        days: newDays,
      );
      _balance = await repository.applyBalanceChange(
        oldType: existing.type,
        oldDays: existing.days,
        newType: type,
        newDays: newDays,
      );
      _requests = await repository.getCachedRequests();
      await onBalanceChanged?.call();
      await sync?.refresh();
      notifyListeners();
      unawaited(_syncInBackground());
      return ActionResult.ok('Leave updated successfully!');
    } catch (error) {
      return ActionResult.fail('Unable to update leave request: $error');
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Deletes a Pending request locally and queues the id for server deletion.
  Future<ActionResult> deleteRequest(String requestId) async {
    final LeaveRequest? existing = _findRequest(requestId);
    if (existing == null) {
      return ActionResult.fail('Leave request not found.');
    }
    if (existing.status != LeaveRequestStatus.pending ||
        existing.syncStatus == SyncStatus.rejected) {
      return ActionResult.fail(
        'Only Pending, non-rejected leave requests can be deleted.',
      );
    }

    try {
      await repository.delete(requestId);
      _balance = await repository.applyBalanceChange(
        oldType: existing.type,
        oldDays: existing.days,
        newType: existing.type,
        newDays: 0,
      );
      _requests = await repository.getCachedRequests();
      await onBalanceChanged?.call();
      await sync?.refresh();
      notifyListeners();
      // Sends the tombstone; if offline it stays queued for reconnection.
      unawaited(_syncInBackground());
      return ActionResult.ok('Leave request deleted.');
    } catch (error) {
      return ActionResult.fail('Unable to delete leave request: $error');
    }
  }

  /// Approves a Pending leave request locally and updates history immediately.
  Future<ActionResult> approveRequest(String requestId) async {
    final LeaveRequest? existing = _findRequest(requestId);
    if (existing == null) {
      return ActionResult.fail('Leave request not found.');
    }
    try {
      await repository.approveRequest(requestId);
      _requests = await repository.getCachedRequests();
      await onBalanceChanged?.call();
      await sync?.refresh();
      notifyListeners();
      return ActionResult.ok('Leave request approved.');
    } catch (error) {
      return ActionResult.fail('Unable to approve leave request: $error');
    }
  }

  LeaveRequest? _findRequest(String id) {
    for (final LeaveRequest request in _requests) {
      if (request.id == id) return request;
    }
    return null;
  }

  /// Best-effort background sync. Failures stay on the queued request and are
  /// never surfaced as a submit error.
  Future<void> _syncInBackground() async {
    if (connectivity.isOffline || sync == null) return;
    await sync!.syncNow(silent: true);
    _requests = await repository.getCachedRequests();
    notifyListeners();
  }

  void _onConnectivityChanged() {
    if (connectivity.isOnline) unawaited(refresh());
  }

  @override
  void dispose() {
    connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}
