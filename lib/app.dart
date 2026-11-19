import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';

import 'constants/app_config.dart';
import 'di.dart';
import 'providers/api_settings_viewmodel.dart';
import 'providers/attendance_viewmodel.dart';
import 'providers/connectivity_viewmodel.dart';
import 'providers/dashboard_viewmodel.dart';
import 'providers/leave_viewmodel.dart';
import 'providers/location_simulation_viewmodel.dart';
import 'providers/office_settings_viewmodel.dart';
import 'providers/sync_viewmodel.dart';
import 'screens/app_shell.dart';

class RebsApp extends StatelessWidget {
  final AppDependencies dependencies;

  const RebsApp({super.key, required this.dependencies});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B5D3B),
      brightness: Brightness.light,
    );

    final List<SingleChildWidget> providers = <SingleChildWidget>[
      ChangeNotifierProvider<ApiSettingsViewModel>.value(
          value: dependencies.apiSettings),
      ChangeNotifierProvider<OfficeSettingsViewModel>.value(
          value: dependencies.officeSettings),
      ChangeNotifierProvider<ConnectivityViewModel>.value(
          value: dependencies.connectivity),
      ChangeNotifierProvider<SyncViewModel>.value(value: dependencies.sync),
      ChangeNotifierProvider<DashboardViewModel>.value(
          value: dependencies.dashboard),
      ChangeNotifierProvider<AttendanceViewModel>.value(
          value: dependencies.attendance),
      ChangeNotifierProvider<LeaveViewModel>.value(value: dependencies.leave),
    ];
    if (dependencies.locationSimulation != null) {
      providers.add(
        ChangeNotifierProvider<LocationSimulationViewModel>.value(
          value: dependencies.locationSimulation!,
        ),
      );
    }

    return MultiProvider(
      providers: providers,
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: const Color(0xFFF4F7F5),
          appBarTheme: AppBarTheme(
            centerTitle: false,
            elevation: 0,
            backgroundColor: scheme.surface,
            foregroundColor: scheme.onSurface,
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: scheme.surface,
            surfaceTintColor: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: scheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        home: const AppShell(),
      ),
    );
  }
}
