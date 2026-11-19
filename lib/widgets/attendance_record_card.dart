import 'package:flutter/material.dart';

import '../models/attendance_record.dart';
import '../models/attendance_status.dart';
import '../utils/company_clock.dart';
import '../utils/date_formats.dart';
import 'status_chip.dart';
import 'sync_status_chip.dart';

class AttendanceRecordCard extends StatelessWidget {
  final AttendanceRecord record;
  final CompanyClock clock;

  const AttendanceRecordCard({
    super.key,
    required this.record,
    required this.clock,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color statusColor = switch (record.status) {
      AttendanceStatus.checkedOut => colors.primary,
      AttendanceStatus.checkedIn => colors.tertiary,
      AttendanceStatus.notCheckedIn => colors.outline,
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
                Icon(Icons.calendar_today_outlined,
                    size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  '${DateFormats.weekday(record.dateKey)}, ${DateFormats.dayMonth(record.dateKey)}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                StatusChip(
                  label: record.status.label,
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Metric(
                    label: 'Check-in',
                    value: DateFormats.eventTime(record.checkIn, clock),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Check-out',
                    value: DateFormats.eventTime(record.checkOut, clock),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Duration',
                    value: DateFormats.duration(record.workingDuration),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                SyncStatusChip(status: record.syncStatus, compact: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.6,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
