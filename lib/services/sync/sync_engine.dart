import '../../models/attendance_event.dart';
import '../../models/attendance_event_type.dart';
import '../../models/leave_request.dart';
import '../../models/sync_status.dart';
import '../../services/api/api_client.dart';
import '../../services/api/api_exceptions.dart';
import '../../services/storage/local_storage.dart';

class SyncSummary {
  final int synced;
  final int rejected;
  final int failed;
  final int pending;
  final List<String> errors;

  const SyncSummary({
    this.synced = 0,
    this.rejected = 0,
    this.failed = 0,
    this.pending = 0,
    this.errors = const <String>[],
  });

  bool get didAnything => synced + rejected + failed > 0;

  @override
  String toString() =>
      'SyncSummary(synced: $synced, rejected: $rejected, failed: $failed, pending: $pending)';
}

/// Sends pending attendance events and pending leave requests in creation
/// order. Both use a client-generated id that never changes, so a retry after
/// a timeout returns the original server receipt instead of a duplicate.
class SyncEngine {
  final ApiClient api;
  final LocalStorage storage;

  SyncEngine({required this.api, required this.storage});

  bool _running = false;

  Future<SyncSummary> syncPending() async {
    if (_running) return const SyncSummary();
    _running = true;
    try {
      int synced = 0;
      int rejected = 0;
      int failed = 0;
      final List<String> errors = <String>[];

      final AttendanceOutcome attendance =
          await _syncAttendance(errors: errors);
      synced += attendance.synced;
      rejected += attendance.rejected;
      failed += attendance.failed;

      final LeaveOutcome leaves = await _syncLeaves(errors: errors);
      synced += leaves.synced;
      rejected += leaves.rejected;
      failed += leaves.failed;

      if (failed == 0 && synced > 0) {
        await storage.setLastSuccessfulSync(DateTime.now().toUtc());
      }

      final int pendingEvents = (await storage.getEvents())
          .where((AttendanceEvent e) =>
              e.syncStatus == SyncStatus.pending ||
              e.syncStatus == SyncStatus.failed)
          .length;
      final int pendingLeaves = (await storage.getLeaveRequests())
          .where((LeaveRequest r) =>
              r.syncStatus == SyncStatus.pending ||
              r.syncStatus == SyncStatus.failed)
          .length;

      return SyncSummary(
        synced: synced,
        rejected: rejected,
        failed: failed,
        pending: pendingEvents + pendingLeaves,
        errors: errors,
      );
    } finally {
      _running = false;
    }
  }

  Future<AttendanceOutcome> _syncAttendance({
    required List<String> errors,
  }) async {
    final List<AttendanceEvent> allEvents = await storage.getEvents();
    final List<AttendanceEvent> pending = allEvents
        .where((AttendanceEvent e) =>
            e.syncStatus == SyncStatus.pending ||
            e.syncStatus == SyncStatus.failed)
        .toList()
      ..sort((AttendanceEvent a, AttendanceEvent b) =>
          a.sequence.compareTo(b.sequence));

    int synced = 0;
    int rejected = 0;
    int failed = 0;

    for (final AttendanceEvent event in pending) {
      final AttendanceEvent attempt =
          event.copyWith(attempts: event.attempts + 1);
      await storage.putEvent(attempt);

      try {
        final AttendanceSubmissionResult receipt =
            await api.submitAttendanceEvent(attempt);
        final String? serverId = receipt.serverId.isEmpty
            ? null
            : receipt.serverId;
        await storage.putEvent(attempt.copyWith(
          syncStatus: SyncStatus.synced,
          serverEventId: serverId,
          lastError: null,
        ));
        synced++;
      } on ApiConflictException catch (error) {
        await storage.putEvent(attempt.copyWith(
          syncStatus: SyncStatus.rejected,
          lastError: error.message,
        ));
        rejected++;
        errors.add(error.message);
      } on ApiValidationException catch (error) {
        await storage.putEvent(attempt.copyWith(
          syncStatus: SyncStatus.rejected,
          lastError: error.message,
        ));
        rejected++;
        errors.add(error.message);
      } catch (error) {
        // Never delete a local event because sync failed.
        await storage.putEvent(attempt.copyWith(
          syncStatus: SyncStatus.failed,
          lastError: error.toString(),
        ));
        failed++;
        // Preserve check-in -> check-out ordering: stop at first failure.
        break;
      }
    }

    return AttendanceOutcome(synced, rejected, failed);
  }

  Future<LeaveOutcome> _syncLeaves({required List<String> errors}) async {
    final List<LeaveRequest> pending = (await storage.getLeaveRequests())
        .where((LeaveRequest r) =>
            r.syncStatus == SyncStatus.pending ||
            r.syncStatus == SyncStatus.failed)
        .toList()
      ..sort((LeaveRequest a, LeaveRequest b) =>
          a.submittedAtUtc.compareTo(b.submittedAtUtc));

    int synced = 0;
    int rejected = 0;
    int failed = 0;

    for (final LeaveRequest request in pending) {
      final LeaveRequest attempt = request.copyWith(
        attempts: request.attempts + 1,
      );
      await _replaceLeave(attempt);

      try {
        final LeaveRequest receipt = await api.submitLeaveRequest(
          type: attempt.type,
          startDate: attempt.startDate,
          endDate: attempt.endDate,
          reason: attempt.reason,
          days: attempt.days,
          requestId: attempt.id,
        );
        final LeaveRequest confirmed = receipt.copyWith(
          syncStatus: SyncStatus.synced,
          attempts: 0,
          lastError: null,
        );
        await _replaceLeave(confirmed, removeId: attempt.id);
        synced++;
      } on ApiValidationException catch (error) {
        // Explicit server refusal is final for this request; keep it in the
        // history with a Rejected sync badge and surface the real message.
        await _replaceLeave(attempt.copyWith(
          syncStatus: SyncStatus.rejected,
          lastError: error.message,
        ));
        rejected++;
        errors.add(error.message);
      } catch (error) {
        await _replaceLeave(attempt.copyWith(
          syncStatus: SyncStatus.failed,
          lastError: error.toString(),
        ));
        failed++;
        break;
      }
    }

    return LeaveOutcome(synced, rejected, failed);
  }

  Future<void> _replaceLeave(
    LeaveRequest request, {
    String? removeId,
  }) async {
    final List<LeaveRequest> cached = await storage.getLeaveRequests();
    final String id = removeId ?? request.id;
    await storage.putLeaveRequests(<LeaveRequest>[
      ...cached.where((LeaveRequest r) => r.id != id),
      request,
    ]);
  }
}

class AttendanceOutcome {
  final int synced;
  final int rejected;
  final int failed;

  const AttendanceOutcome(this.synced, this.rejected, this.failed);
}

class LeaveOutcome {
  final int synced;
  final int rejected;
  final int failed;

  const LeaveOutcome(this.synced, this.rejected, this.failed);
}
