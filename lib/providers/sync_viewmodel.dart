import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/action_result.dart';
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
    _pendingCount = events
            .where((event) =>
                event.syncStatus == SyncStatus.pending ||
                event.syncStatus == SyncStatus.failed)
            .length +
        leaves
            .where((request) =>
                request.syncStatus == SyncStatus.pending ||
                request.syncStatus == SyncStatus.failed)
            .length;
    _lastSuccessfulSync = await storage.getLastSuccessfulSync();
    notifyListeners();
  }

  Future<ActionResult> syncNow({bool silent = false}) async {
    if (_isSyncing) {
      return const ActionResult(success: true, message: 'Sync already running.');
    }
    if (connectivity.isOffline) {
      const String message =
          'You are offline. Pending events will sync automatically when the connection returns.';
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
      if (!summary.didAnything) {
        message = 'Everything is already synced.';
      } else {
        message = 'Sync complete: ${summary.synced} synced, '
            '${summary.rejected} rejected, ${summary.failed} failed. '
            '${summary.pending} still pending.';
        if (summary.errors.isNotEmpty) {
          message += ' ${summary.errors.first}';
        }
      }
      if (!silent) _lastMessage = message;
      notifyListeners();
      return ActionResult(success: summary.failed == 0, message: message);
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
