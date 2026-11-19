import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/action_result.dart';
import '../providers/attendance_viewmodel.dart';
import '../providers/dashboard_viewmodel.dart';
import '../providers/leave_viewmodel.dart';
import '../providers/sync_viewmodel.dart';

/// Runs a manual sync, refreshes all attendance and leave surfaces so their
/// badges move from Saved Locally to Synced immediately, and reports the outcome.
///
/// Used by the Dashboard cloud icon, the Attendance sync card, and the per-row
/// Retry action so all three give identical feedback.
Future<void> runSyncWithFeedback(BuildContext context) async {
  final SyncViewModel sync = context.read<SyncViewModel>();
  final DashboardViewModel dashboard = context.read<DashboardViewModel>();
  final AttendanceViewModel attendance = context.read<AttendanceViewModel>();
  final LeaveViewModel leave = context.read<LeaveViewModel>();

  final ActionResult result = await sync.syncNow();

  // Always republish after a sync attempt, even a failed one: the event status
  // may have changed from Pending to Saved Locally.
  await dashboard.reloadLocal();
  await attendance.reloadLocal();
  await leave.reloadLocal();

  if (!context.mounted) return;
  final ColorScheme colors = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(result.message),
      backgroundColor: result.success ? null : colors.error,
    ),
  );
}

/// Clears pending / failed queue items and reloads all views so the pending
/// badge and any failed error banners clear immediately.
Future<void> runClearPendingWithFeedback(BuildContext context) async {
  final SyncViewModel sync = context.read<SyncViewModel>();
  final DashboardViewModel dashboard = context.read<DashboardViewModel>();
  final AttendanceViewModel attendance = context.read<AttendanceViewModel>();
  final LeaveViewModel leave = context.read<LeaveViewModel>();

  final ActionResult result = await sync.clearPending();

  await dashboard.reloadLocal();
  await attendance.reloadLocal();
  await leave.reloadLocal();

  if (!context.mounted) return;
  final ColorScheme colors = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(result.message),
      backgroundColor: result.success ? null : colors.error,
    ),
  );
}
