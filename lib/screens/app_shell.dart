import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/attendance_viewmodel.dart';
import '../providers/connectivity_viewmodel.dart';
import '../providers/dashboard_viewmodel.dart';
import '../providers/leave_viewmodel.dart';
import '../providers/sync_viewmodel.dart';
import '../widgets/state_views.dart';
import '../widgets/sync_feedback.dart';
import 'attendance_screen.dart';
import 'dashboard_screen.dart';
import 'leave_screen.dart';
import 'profile_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final GlobalKey<DashboardScreenState> _dashboardKey =
      GlobalKey<DashboardScreenState>();
  final GlobalKey<AttendanceScreenState> _attendanceKey =
      GlobalKey<AttendanceScreenState>();

  static const List<String> _titles = <String>[
    'Dashboard',
    'Attendance',
    'Leave',
    'Profile',
  ];

  late final List<Widget> _pages = <Widget>[
    DashboardScreen(key: _dashboardKey),
    AttendanceScreen(key: _attendanceKey),
    const LeaveScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Load each ViewModel once; tab changes reuse the same instances.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardViewModel>().load();
      context.read<AttendanceViewModel>().load();
      context.read<LeaveViewModel>().load();
    });
  }

  Future<void> _syncNow() => runSyncWithFeedback(context);

  Future<void> _handleSyncTap(SyncViewModel sync) async {
    if (sync.pendingCount > 0) {
      await _showSyncSheet(context, sync);
    } else {
      await _syncNow();
    }
  }

  Future<void> _showSyncSheet(BuildContext context, SyncViewModel sync) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.cloud_sync_outlined,
                      color: Theme.of(sheetContext).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Synchronization',
                      style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Theme.of(sheetContext).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${sync.pendingCount} pending',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'There are ${sync.pendingCount} record(s) saved locally waiting to sync with the server. '
                  'If the server is unavailable or you want to reset the pending badge, you can clear the queue.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: sync.isSyncing
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop();
                          _syncNow();
                        },
                  icon: const Icon(Icons.sync),
                  label: Text(sync.isSyncing ? 'Syncing…' : 'Sync Now'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    runClearPendingWithFeedback(context);
                  },
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Clear / Reset Pending Queue'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_index],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          Consumer<SyncViewModel>(
            builder: (BuildContext context, SyncViewModel sync, _) {
              return Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  IconButton(
                    tooltip: sync.pendingCount > 0
                        ? 'Sync options — ${sync.pendingCount} record(s) waiting'
                        : 'Sync Now',
                    onPressed: sync.isSyncing ? null : () => _handleSyncTap(sync),
                    icon: sync.isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_sync_outlined),
                  ),
                  if (sync.pendingCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${sync.pendingCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: <Widget>[
          Consumer<ConnectivityViewModel>(
            builder: (BuildContext context, ConnectivityViewModel vm, _) =>
                OfflineBanner(visible: vm.isOffline),
          ),
          Expanded(
            child: IndexedStack(index: _index, children: _pages),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int index) {
          if (index == 0) {
            _dashboardKey.currentState?.reloadWith2sLoading();
          } else if (index == 1) {
            _attendanceKey.currentState?.reloadWith2sLoading();
          }
          setState(() => _index = index);
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.fingerprint_outlined),
            selectedIcon: Icon(Icons.fingerprint),
            label: 'Attendance',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Leave',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
