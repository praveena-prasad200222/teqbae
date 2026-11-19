import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_config.dart';
import '../models/action_result.dart';
import '../models/attendance_event_type.dart';
import '../models/attendance_status.dart';
import '../models/office_location.dart';
import '../models/sync_status.dart';
import '../providers/attendance_viewmodel.dart';
import '../providers/location_simulation_viewmodel.dart';
import '../providers/office_settings_viewmodel.dart';
import '../providers/sync_viewmodel.dart';
import '../providers/view_state.dart';
import '../utils/company_clock.dart';
import '../utils/date_formats.dart';
import '../widgets/attendance_record_card.dart';
import '../widgets/section_header.dart';
import '../widgets/state_views.dart';
import '../widgets/sync_feedback.dart';

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AttendanceViewModel>(
      builder: (BuildContext context, AttendanceViewModel vm, _) {
        if (vm.state == ViewState.initial || vm.state == ViewState.loading) {
          return const LoadingView(message: 'Loading attendance…');
        }
        if (vm.state == ViewState.error) {
          return ErrorView(
            message: vm.errorMessage ?? 'Unable to load attendance.',
            onRetry: vm.load,
          );
        }

        final AttendanceStatus status =
            vm.todayRecord?.status ?? AttendanceStatus.notCheckedIn;
        final CompanyClock clock = vm.clock;

        return RefreshIndicator(
          onRefresh: vm.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            "Today's status",
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (status != AttendanceStatus.notCheckedIn)
                            TextButton.icon(
                              onPressed: vm.isProcessing
                                  ? null
                                  : () => _resetAttendance(context, vm),
                              icon: const Icon(Icons.restart_alt_outlined, size: 16),
                              label: const Text('Reset', style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        status.label,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _TimeTile(
                              icon: Icons.login_outlined,
                              label: 'Check-in',
                              time: DateFormats.eventTime(
                                  vm.todayRecord?.checkIn, clock),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _TimeTile(
                              icon: Icons.logout_outlined,
                              label: 'Check-out',
                              time: DateFormats.eventTime(
                                  vm.todayRecord?.checkOut, clock),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Working duration: ${DateFormats.duration(vm.todayRecord?.workingDuration ?? vm.todayRecord?.workingDurationAt(clock.utcNow))}${vm.todayRecord?.checkIn != null && vm.todayRecord?.checkOut == null ? " (in progress)" : ""}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: vm.isProcessing || status != AttendanceStatus.notCheckedIn
                          ? null
                          : () => _confirmAndRecord(
                                context,
                                vm,
                                AttendanceEventType.checkIn,
                              ),
                      icon: const Icon(Icons.login_outlined),
                      label: const Text('Check In'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: vm.isProcessing || status != AttendanceStatus.checkedIn
                          ? null
                          : () => _confirmAndRecord(
                                context,
                                vm,
                                AttendanceEventType.checkOut,
                              ),
                      icon: const Icon(Icons.logout_outlined),
                      label: const Text('Check Out'),
                    ),
                  ),
                ],
              ),
              if (status == AttendanceStatus.checkedOut) ...<Widget>[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: vm.isProcessing
                        ? null
                        : () => _resetAttendance(context, vm),
                    icon: const Icon(Icons.restart_alt_outlined),
                    label: const Text('Reset session & check in again'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                vm.isProcessing
                    ? 'Recording attendance…'
                    : status == AttendanceStatus.checkedOut
                        ? 'One session per day is allowed. Come back tomorrow for a new session.'
                        : status == AttendanceStatus.checkedIn
                            ? 'Check-out is available after a successful check-in.'
                            : 'Check-in is available once per working day, within the office geofence.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (LocationSimulationViewModel.isSupported) ...<Widget>[
                const _OfficeCoordinatesCard(),
                _buildGpsDebugCard(context, vm),
              ],
              const SizedBox(height: 18),
              const SectionHeader(title: 'Synchronization'),
              const SizedBox(height: 10),
              const _SyncCard(),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Attendance history'),
              const SizedBox(height: 10),
              if (vm.records.isEmpty)
                const EmptyView(
                  message: 'No attendance records yet.',
                  icon: Icons.history_toggle_off_outlined,
                )
              else
                ...vm.records.map(
                  (record) => AttendanceRecordCard(
                    record: record,
                    clock: clock,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmAndRecord(
    BuildContext context,
    AttendanceViewModel vm,
    AttendanceEventType type,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Confirm ${type.label.toLowerCase()}'),
        content: Text(
          'Your current GPS location and the exact time will be recorded. '
          'This action is only valid within the configured office radius.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ActionResult result = type == AttendanceEventType.checkIn
        ? await vm.checkIn()
        : await vm.checkOut();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _resetAttendance(
    BuildContext context,
    AttendanceViewModel vm,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Reset today\'s session?'),
        content: const Text(
          'This will clear your check-in and check-out so you can check in again. '
          'Your previous 5 history records will not be changed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ActionResult result = await vm.resetTodayAttendance();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Widget _buildGpsDebugCard(
    BuildContext context,
    AttendanceViewModel attendance,
  ) {
    return Consumer<LocationSimulationViewModel>(
      builder: (
        BuildContext context,
        LocationSimulationViewModel gps,
        _,
      ) {
        final ColorScheme colors = Theme.of(context).colorScheme;
        final OfficeLocation office = attendance.effectiveOffice;
        final double distance = gps.distanceFrom(office);
        final bool inside = gps.isWithinOffice(office);
        final bool simulating = gps.simulationEnabled;
        final bool configured = office.isConfigured;

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: configured && inside
                  ? colors.primaryContainer
                  : colors.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: simulating,
                  onChanged: (bool value) {
                    gps.setSimulationEnabled(value);
                    // Turning simulation on must produce a usable point. If the
                    // last saved simulated point is outside (or was never set),
                    // snap it inside the office so Check In works immediately.
                    if (value && configured && !inside) {
                      gps.useInsideOfficePreset(office);
                    }
                  },
                  title: const Text(
                    'GPS Simulation (DEBUG)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    simulating
                        ? 'Simulated coordinates are being used for check-in/out.'
                        : 'Real device GPS is active. Turn this on to test '
                            'Check In indoors.',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  configured
                      ? 'Distance from ${office.name}: ${distance.toStringAsFixed(1)} m — '
                          '${inside ? 'inside' : 'outside'} the '
                          '${office.radiusMeters.round()} m geofence.'
                      : 'Office coordinates are not configured. '
                          '${AppConfig.officeConfigurationHint}',
                  style: TextStyle(
                    fontSize: 12,
                    color: configured && inside
                        ? colors.onPrimaryContainer
                        : colors.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    TextButton(
                      onPressed: configured
                          ? () => gps.useInsideOfficePreset(office)
                          : null,
                      child: const Text('Inside 200 m'),
                    ),
                    TextButton(
                      onPressed: configured
                          ? () => gps.useOutsideOfficePreset(office)
                          : null,
                      child: const Text('Outside 200 m'),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Debug builds only. The 200 m rule is enforced for every '
                  'simulated coordinate.',
                  style: TextStyle(
                    fontSize: 10,
                    color: configured && inside
                        ? colors.onPrimaryContainer
                        : colors.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TimeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String time;

  const _TimeTile({
    required this.icon,
    required this.label,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    time,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficeCoordinatesCard extends StatefulWidget {
  const _OfficeCoordinatesCard();

  @override
  State<_OfficeCoordinatesCard> createState() => _OfficeCoordinatesCardState();
}

class _OfficeCoordinatesCardState extends State<_OfficeCoordinatesCard> {
  final TextEditingController _latitude = TextEditingController();
  final TextEditingController _longitude = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OfficeSettingsViewModel settings =
        context.watch<OfficeSettingsViewModel>();
    if (!_initialized) {
      _latitude.text = settings.latitude?.toString() ?? '';
      _longitude.text = settings.longitude?.toString() ?? '';
      _initialized = true;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Test office coordinates (DEBUG)',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                settings.isConfigured
                    ? 'Active: ${settings.latitude}, ${settings.longitude}'
                    : 'Not set. Enter any test latitude/longitude to enable the '
                        '200 m geofence simulation.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _latitude,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _longitude,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: () => _save(context, settings),
                child: const Text('Save test office'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    OfficeSettingsViewModel settings,
  ) async {
    final ActionResult result = await settings.saveCoordinates(
      _latitude.text,
      _longitude.text,
    );
    if (!context.mounted) return;
    if (result.success) {
      // Make the new reference usable immediately: put the simulated point at
      // the office and turn simulation on. The switch can still turn it off.
      final LocationSimulationViewModel gps =
          context.read<LocationSimulationViewModel>();
      gps.useInsideOfficePreset(settings.office);
      gps.setSimulationEnabled(true);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncViewModel>(
      builder: (BuildContext context, SyncViewModel sync, _) {
        final ColorScheme colors = Theme.of(context).colorScheme;
        final String statusText = sync.pendingCount == 0
            ? 'All attendance and leave records are synced.'
            : '${sync.pendingCount} record(s) are saved on this device and '
                'waiting to sync.';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Icon(
                  sync.pendingCount == 0
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_upload_outlined,
                  color: sync.pendingCount == 0 ? colors.primary : colors.tertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        sync.pendingCount == 0
                            ? SyncStatus.synced.label
                            : SyncStatus.pending.label,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(statusText,
                          style: TextStyle(
                              fontSize: 11, color: colors.onSurfaceVariant)),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: sync.isSyncing
                      ? null
                      : () => runSyncWithFeedback(context),
                  child: Text(sync.isSyncing ? 'Syncing…' : 'Sync Now'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
