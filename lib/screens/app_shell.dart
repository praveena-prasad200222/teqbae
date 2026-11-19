import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/action_result.dart';
import '../providers/attendance_viewmodel.dart';
import '../providers/connectivity_viewmodel.dart';
import '../providers/dashboard_viewmodel.dart';
import '../providers/leave_viewmodel.dart';
import '../providers/sync_viewmodel.dart';
import '../widgets/state_views.dart';
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

  static const List<String> _titles = <String>[
    'Dashboard',
    'Attendance',
    'Leave',
    'Profile',
  ];

  static const List<Widget> _pages = <Widget>[
    DashboardScreen(),
    AttendanceScreen(),
    LeaveScreen(),
    ProfileScreen(),
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

  Future<void> _syncNow() async {
    final ActionResult result = await context.read<SyncViewModel>().syncNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? null : Theme.of(context).colorScheme.error,
      ),
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
                    tooltip: 'Sync Now',
                    onPressed: sync.isSyncing ? null : _syncNow,
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
                          color: Theme.of(context).colorScheme.error,
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
        onDestinationSelected: (int index) => setState(() => _index = index),
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
