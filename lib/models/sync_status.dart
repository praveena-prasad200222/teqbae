/// Sync states required by the assignment.
///
/// [pending] has not been attempted yet, [failed] is retryable after a network
/// or server failure, and [rejected] is an explicit server refusal.
enum SyncStatus { pending, synced, failed, rejected }

extension SyncStatusX on SyncStatus {
  String get label => switch (this) {
        SyncStatus.pending => 'Pending Sync',
        SyncStatus.synced => 'Synced',
        SyncStatus.failed => 'Failed',
        SyncStatus.rejected => 'Rejected',
      };

  String get jsonValue => name;

  static SyncStatus fromJson(String value) => switch (value) {
        'synced' => SyncStatus.synced,
        'failed' => SyncStatus.failed,
        'rejected' => SyncStatus.rejected,
        _ => SyncStatus.pending,
      };
}
