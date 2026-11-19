import 'package:flutter/material.dart';

import '../models/leave_request.dart';
import '../models/leave_request_status.dart';
import '../models/leave_type.dart';
import '../models/sync_status.dart';
import '../utils/date_formats.dart';
import 'status_chip.dart';

class LeaveRequestCard extends StatelessWidget {
  final LeaveRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const LeaveRequestCard({
    super.key,
    required this.request,
    this.onApprove,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color statusColor = switch (request.status) {
      LeaveRequestStatus.approved => colors.primary,
      LeaveRequestStatus.pending => colors.tertiary,
      LeaveRequestStatus.rejected => colors.error,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.event_available_outlined,
                    size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  '${request.type.label} leave',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (request.syncStatus != SyncStatus.synced)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: StatusChip(
                      label: request.syncStatus.label,
                      color: request.syncStatus == SyncStatus.pending
                          ? colors.tertiary
                          : colors.error,
                    ),
                  ),
                StatusChip(label: request.status.label, color: statusColor),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${DateFormats.dayMonth(request.startDate)} – ${DateFormats.dayMonth(request.endDate)}  •  ${request.days} day(s)',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              request.reason,
              style: const TextStyle(fontSize: 13),
            ),
            if (request.lastError != null &&
                !request.lastError!.contains('Cannot reach') &&
                !request.lastError!.contains('SocketException') &&
                !request.lastError!.contains('TimeoutException') &&
                !request.lastError!.contains('ClientException') &&
                request.status != LeaveRequestStatus.approved &&
                request.syncStatus != SyncStatus.synced) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                request.lastError!,
                style: TextStyle(fontSize: 11, color: colors.error),
              ),
            ],
            if (onApprove != null || onEdit != null || onDelete != null) ...<Widget>[
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (onApprove != null)
                    FilledButton.tonalIcon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_circle_outlined, size: 18),
                      label: const Text('Approve'),
                    ),
                  if (onApprove != null && (onEdit != null || onDelete != null))
                    const SizedBox(width: 8),
                  if (onEdit != null)
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  if (onDelete != null)
                    TextButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.error,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
