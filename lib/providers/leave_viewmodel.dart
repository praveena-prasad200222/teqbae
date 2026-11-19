import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/action_result.dart';
import '../models/leave_balance.dart';
import '../models/leave_request.dart';
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

  LeaveViewModel({
    required this.repository,
    required this.connectivity,
    required this.clock,
    this.sync,
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
          r.syncStatus == SyncStatus.pending ||
          r.syncStatus == SyncStatus.failed)
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
      _requests = await repository.getCachedRequests();
      await sync?.refresh();
      notifyListeners();

      // Foreground submission is deliberately local-only. A slow or broken API
      // must never block the employee from filing leave. The sync engine owns
      // all network attempts and reports validation/server errors on the card.
      unawaited(_syncInBackground());
      return ActionResult.ok(
        connectivity.isOffline
            ? 'Saved locally as Pending Sync. Your leave request will be '
                'submitted automatically when the connection returns.'
            : 'Saved locally as Pending Sync. It will be submitted in the '
                'background; no API error can block this form.',
      );
    } catch (error) {
      return ActionResult.fail('Unable to save leave request: $error');
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
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
