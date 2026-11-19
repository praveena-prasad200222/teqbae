import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/attendance_record.dart';
import '../models/attendance_status.dart';
import '../models/employee.dart';
import '../models/leave_balance.dart';
import '../providers/dashboard_viewmodel.dart';
import '../providers/view_state.dart';
import '../utils/company_clock.dart';
import '../utils/date_formats.dart';
import '../widgets/attendance_record_card.dart';
import '../widgets/info_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/state_views.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardViewModel>(
      builder: (BuildContext context, DashboardViewModel vm, _) {
        if (vm.state == ViewState.initial || vm.state == ViewState.loading) {
          return const LoadingView(message: 'Loading your workspace…');
        }
        if (vm.state == ViewState.error) {
          return ErrorView(
            message: vm.errorMessage ?? 'Unable to load the dashboard.',
            onRetry: vm.load,
          );
        }

        final Employee employee = vm.employee ?? Employee.fallback();
        final LeaveBalance balance = vm.balance ?? LeaveBalance.empty;
        final AttendanceRecord? today = vm.todayRecord;

        return RefreshIndicator(
          onRefresh: vm.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              _EmployeeHeader(employee: employee, offline: vm.isOffline),
              if (vm.isRefreshing)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              // The five demo records and cached employee/balance are always
              // available locally, so an unreachable mock server must not turn
              // the dashboard into an error screen. Pull-to-refresh still
              // retries silently.
              if (vm.refreshError != null && vm.latestRecords.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _RefreshErrorBanner(
                    message: vm.refreshError!,
                    onRetry: vm.refresh,
                  ),
                ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool wide = constraints.maxWidth >= 720;
                  final List<Widget> cards = <Widget>[
                    _TodayCard(record: today, clock: vm.clock),
                    _BalanceCard(balance: balance, clock: vm.clock),
                  ];
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: cards[0]),
                        const SizedBox(width: 12),
                        Expanded(child: cards[1]),
                      ],
                    );
                  }
                  return Column(
                    children: <Widget>[
                      cards[0],
                      const SizedBox(height: 12),
                      cards[1],
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'History'),
              const SizedBox(height: 10),
              if (vm.latestRecords.isEmpty)
                const EmptyView(
                  message: 'No attendance records yet. Your recent history will appear here.',
                  icon: Icons.history_toggle_off_outlined,
                )
              else
                ...vm.latestRecords.map(
                  (AttendanceRecord record) => AttendanceRecordCard(
                    record: record,
                    clock: vm.clock,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EmployeeHeader extends StatelessWidget {
  final Employee employee;
  final bool offline;

  const _EmployeeHeader({required this.employee, required this.offline});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 28,
            backgroundColor: colors.onPrimary.withValues(alpha: 0.18),
            child: Text(
              employee.name.isEmpty ? '?' : employee.name[0],
              style: TextStyle(
                color: colors.onPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    color: colors.onPrimary.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  employee.name,
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${employee.id}  •  ${employee.department}',
                  style: TextStyle(
                    color: colors.onPrimary.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (offline)
            Icon(Icons.cloud_off_outlined,
                color: colors.onPrimary.withValues(alpha: 0.9)),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final AttendanceRecord? record;
  final CompanyClock clock;

  const _TodayCard({required this.record, required this.clock});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              "Today's attendance",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            InfoTile(
              icon: Icons.info_outline,
              label: 'Status',
              value: record?.status.label ?? 'Not Checked In',
            ),
            const SizedBox(height: 12),
            InfoTile(
              icon: Icons.login_outlined,
              label: 'Check-in time',
              value: DateFormats.eventTime(record?.checkIn, clock),
            ),
            const SizedBox(height: 12),
            InfoTile(
              icon: Icons.logout_outlined,
              label: 'Check-out time',
              value: DateFormats.eventTime(record?.checkOut, clock),
            ),
            const SizedBox(height: 12),
            InfoTile(
              icon: Icons.schedule_outlined,
              label: 'Working duration',
              value: DateFormats.duration(record?.workingDuration),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final LeaveBalance balance;
  final CompanyClock clock;

  const _BalanceCard({required this.balance, required this.clock});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Leave balance',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _BalanceTile(
                    label: 'Casual',
                    value: '${balance.casual}',
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BalanceTile(
                    label: 'Sick',
                    value: '${balance.sick}',
                    color: colors.tertiary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BalanceTile(
                    label: 'Total',
                    value: '${balance.total}',
                    color: colors.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Company date: ${clock.dateKey(clock.utcNow)}',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BalanceTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: <Widget>[
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}

class _RefreshErrorBanner extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _RefreshErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.cloud_off_outlined,
              size: 18, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11, color: colors.onErrorContainer),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(onRetry()),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
