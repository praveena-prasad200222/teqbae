/// Sync states required by the assignment.
///
/// [pending] has not been attempted yet, [failed] is retryable after a network
/// or server failure, and [rejected] is an explicit server refusal.
enum SyncStatus { pending, synced, failed, rejected }

extension SyncStatusX on SyncStatus {
  String get label => switch (this) {
        SyncStatus.pending => 'Pending Sync',
        SyncStatus.synced => 'Synced',
        // The record is safe on this device; only the upload attempt failed.
        // Keeping the wording non-alarming avoids implying that data was lost.
        SyncStatus.failed => 'Saved Locally',
        SyncStatus.rejected => 'Rejected',
      };

  /// Longer explanation used by tooltips and status cards.
  String get description => switch (this) {
        SyncStatus.pending => 'Waiting to be uploaded.',
        SyncStatus.synced => 'Uploaded to the server.',
        SyncStatus.failed =>
          'Saved on this device. It will retry automatically when the server is reachable.',
        SyncStatus.rejected => 'The server refused this record.',
      };

  String get jsonValue => name;

  static SyncStatus fromJson(String value) => switch (value) {
        'synced' => SyncStatus.synced,
        'failed' => SyncStatus.failed,
        'rejected' => SyncStatus.rejected,
        _ => SyncStatus.pending,
      };
}
