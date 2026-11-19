import 'package:flutter/material.dart';

import '../models/sync_status.dart';

class SyncStatusChip extends StatelessWidget {
  final SyncStatus status;
  final bool compact;

  const SyncStatusChip({
    super.key,
    required this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final (Color foreground, Color background, IconData icon) =
        switch (status) {
      SyncStatus.synced => (
          colors.primary,
          colors.primary.withValues(alpha: 0.10),
          Icons.cloud_done_outlined
        ),
      SyncStatus.pending => (
          colors.tertiary,
          colors.tertiary.withValues(alpha: 0.14),
          Icons.schedule
        ),
      SyncStatus.failed => (
          colors.tertiary,
          colors.tertiary.withValues(alpha: 0.14),
          Icons.cloud_upload_outlined
        ),
      SyncStatus.rejected => (
          colors.error,
          colors.error.withValues(alpha: 0.10),
          Icons.report_problem_outlined
        ),
    };

    return Tooltip(
      message: status.description,
      child: Chip(
        avatar: Icon(icon, size: 14, color: foreground),
        label: Text(
          status.label,
          style: TextStyle(
            color: foreground,
            fontSize: compact ? 10 : 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: background,
        side: BorderSide.none,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
