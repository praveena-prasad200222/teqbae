import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/action_result.dart';
import '../models/attendance_event.dart';
import '../models/leave_request.dart';
import '../models/leave_request_status.dart';
import '../models/sync_status.dart';
import '../services/storage/local_storage.dart';
import '../services/sync/sync_engine.dart';
import 'connectivity_viewmodel.dart';

class SyncViewModel extends ChangeNotifier {
  final SyncEngine engine;
  final LocalStorage storage;
  final ConnectivityViewModel connectivity;

  SyncViewModel({
    required this.engine,
    required this.storage,
    required this.connectivity,
  }) {
    connectivity.addListener(_onConnectivityChanged);
  }

  bool _isSyncing = false;
  bool _wasOnline = true;
  int _pendingCount = 0;
  DateTime? _lastSuccessfulSync;
  String? _lastMessage;

  bool get isSyncing => _isSyncing;
  int get pendingCount => _pendingCount;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;
  String? get lastMessage => _lastMessage;

  Future<void> init() async {
    await refresh();
    _wasOnline = connectivity.isOnline;
    if (_wasOnline) {
      await syncNow(silent: true);
    }
  }

  /// Recomputes pending count and last-sync timestamp from persistence.
  Future<void> refresh() async {
    final events = await storage.getEvents();
    final leaves = await storage.getLeaveRequests();
    final deletions = await storage.getLeaveDeletionQueue();
    _pendingCount = events
            .where((event) =>
                event.syncStatus == SyncStatus.pending ||
                event.syncStatus == SyncStatus.failed)
            .length +
        leaves
            .where((request) =>
                request.status != LeaveRequestStatus.approved &&
                (request.syncStatus == SyncStatus.pending ||
                    request.syncStatus == SyncStatus.failed))
            .length +
        deletions.length;
    _lastSuccessfulSync = await storage.getLastSuccessfulSync();
    notifyListeners();
  }

  /// Clears stuck/failed pending records and queued deletions from local persistence.
  Future<ActionResult> clearPending() async {
    try {
      // 1. Clear queued leave deletions
      await storage.putLeaveDeletionQueue(<String>[]);

      // 2. Mark any pending or failed leave requests as approved & synced and clear errors
      final List<LeaveRequest> leaves = await storage.getLeaveRequests();
      final List<LeaveRequest> updatedLeaves = leaves.map((LeaveRequest r) {
        if (r.syncStatus == SyncStatus.failed ||
            r.syncStatus == SyncStatus.pending ||
            r.lastError != null) {
          return r.copyWith(
            status: LeaveRequestStatus.approved,
            syncStatus: SyncStatus.synced,
            clearLastError: true,
            attempts: 0,
          );
        }
        return r;
      }).toList();
      await storage.putLeaveRequests(updatedLeaves);

      // 3. Mark any pending or failed attendance events as synced
      final List<AttendanceEvent> events = await storage.getEvents();
      for (final AttendanceEvent event in events) {
        if (event.syncStatus == SyncStatus.failed ||
            event.syncStatus == SyncStatus.pending) {
          await storage.putEvent(event.copyWith(
            syncStatus: SyncStatus.synced,
          ));
        }
      }

      await refresh();
      _lastMessage = 'Pending sync records cleared.';
      notifyListeners();
      return ActionResult.ok('Pending sync records cleared.');
    } catch (error) {
      final String msg = 'Failed to clear pending records: $error';
      _lastMessage = msg;
      notifyListeners();
      return ActionResult.fail(msg);
    }
  }

  Future<ActionResult> syncNow({bool silent = false}) async {
    if (_isSyncing) {
      return const ActionResult(success: true, message: 'Sync already running.');
    }
    if (connectivity.isOffline) {
      final String message = _pendingCount == 0
          ? 'You are offline. Everything is saved on this device.'
          : 'You are offline. $_pendingCount record(s) are waiting to sync. '
              'Reconnect and tap Sync again.';
      if (!silent) _lastMessage = message;
      notifyListeners();
      return ActionResult.fail(message);
    }

    _isSyncing = true;
    notifyListeners();
    try {
      final SyncSummary summary = await engine.syncPending();
      await refresh();

      String message;
      if (summary.rejected > 0) {
        message = '${summary.rejected} request(s) were rejected by the server. '
            '${summary.synced} synced, ${summary.pending} still pending.';
      } else if (summary.failed > 0) {
        final String detail = summary.errors.isNotEmpty
            ? summary.errors.first
            : 'The server could not be reached.';
        message = '${summary.failed} record(s) failed to sync. $detail';
      } else if (!summary.didAnything && summary.pending == 0) {
        message = 'Everything is already synced.';
      } else if (summary.pending == 0) {
        message = 'Sync complete. Everything is up to date.';
      } else {
        message = 'Sync complete: ${summary.synced} synced, '
            '${summary.pending} still pending.';
      }
      if (!silent) _lastMessage = message;
      notifyListeners();
      return ActionResult(
        success: summary.failed == 0 && summary.rejected == 0,
        message: message,
      );
    } catch (error) {
      final String message = 'Sync failed: $error';
      if (!silent) _lastMessage = message;
      notifyListeners();
      return ActionResult.fail(message);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  void _onConnectivityChanged() {
    final bool online = connectivity.isOnline;
    if (online && !_wasOnline) {
      _wasOnline = true;
      unawaited(syncNow(silent: true));
    } else if (!online) {
      _wasOnline = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}
