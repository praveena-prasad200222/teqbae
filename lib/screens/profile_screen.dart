import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_config.dart';
import '../models/action_result.dart';
import '../models/employee.dart';
import '../models/office_location.dart';
import '../providers/api_settings_viewmodel.dart';
import '../providers/dashboard_viewmodel.dart';
import '../providers/location_simulation_viewmodel.dart';
import '../providers/office_settings_viewmodel.dart';
import '../providers/sync_viewmodel.dart';
import '../widgets/info_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/sync_feedback.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _latitudeController =
      TextEditingController(text: AppConfig.mockLatitude.toStringAsFixed(6));
  late final TextEditingController _longitudeController =
      TextEditingController(text: AppConfig.mockLongitude.toStringAsFixed(6));
  final TextEditingController _apiBaseUrlController =
      TextEditingController();
  bool _apiUrlControllerInitialized = false;

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();
    _apiBaseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Employee employee =
        context.watch<DashboardViewModel>().employee ?? Employee.fallback();
    final OfficeSettingsViewModel officeSettings =
        context.watch<OfficeSettingsViewModel>();
    final OfficeLocation office = employee.office.isConfigured
        ? employee.office
        : officeSettings.office;
    final ApiSettingsViewModel apiSettings =
        context.watch<ApiSettingsViewModel>();
    if (!_apiUrlControllerInitialized) {
      _apiBaseUrlController.text = apiSettings.baseUrl;
      _apiUrlControllerInitialized = true;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: <Widget>[
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    employee.name.isEmpty ? '?' : employee.name[0],
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  employee.name,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800),
                ),
                Text(
                  employee.designation,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Chip(label: Text(employee.id)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Employee details'),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                InfoTile(
                  icon: Icons.badge_outlined,
                  label: 'Employee ID',
                  value: employee.id,
                ),
                const SizedBox(height: 14),
                InfoTile(
                  icon: Icons.business_outlined,
                  label: 'Department',
                  value: employee.department,
                ),
                const SizedBox(height: 14),
                InfoTile(
                  icon: Icons.mail_outline,
                  label: 'Email',
                  value: employee.email,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Office configuration'),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                InfoTile(
                  icon: Icons.location_city_outlined,
                  label: 'Office',
                  value: employee.office.name,
                ),
                const SizedBox(height: 14),
                InfoTile(
                  icon: Icons.my_location_outlined,
                  label: 'Coordinates',
                  value: office.isConfigured
                      ? '${office.latitude.toStringAsFixed(5)}, ${office.longitude.toStringAsFixed(5)}'
                      : 'Not configured — ${AppConfig.officeConfigurationHint}',
                ),
                const SizedBox(height: 14),
                InfoTile(
                  icon: Icons.radar_outlined,
                  label: 'Allowed radius',
                  value: '${employee.office.radiusMeters.round()} m',
                ),
                const SizedBox(height: 14),
                InfoTile(
                  icon: Icons.schedule_outlined,
                  label: 'Company timezone',
                  value: AppConfig.companyTimezoneLabel,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Synchronization'),
        const SizedBox(height: 10),
        Consumer<SyncViewModel>(
          builder: (BuildContext context, SyncViewModel sync, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  InfoTile(
                    icon: Icons.pending_actions_outlined,
                    label: 'Pending events',
                    value: '${sync.pendingCount}',
                  ),
                  const SizedBox(height: 14),
                  InfoTile(
                    icon: Icons.check_circle_outline,
                    label: 'Last successful sync',
                    value: sync.lastSuccessfulSync == null
                        ? 'Never'
                        : sync.lastSuccessfulSync!.toIso8601String(),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.tonal(
                        onPressed: sync.isSyncing
                            ? null
                            : () => runSyncWithFeedback(context),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.cloud_sync_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text(sync.isSyncing ? 'Syncing…' : 'Sync Now'),
                          ],
                        ),
                      ),
                      if (sync.pendingCount > 0)
                        OutlinedButton(
                          onPressed: () => runClearPendingWithFeedback(context),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.cleaning_services_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Clear Pending Queue'),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (LocationSimulationViewModel.isSupported) ...<Widget>[
          const SizedBox(height: 20),
          const SectionHeader(title: 'Development GPS simulation'),
          const SizedBox(height: 10),
          Consumer<LocationSimulationViewModel>(
            builder: (
              BuildContext context,
              LocationSimulationViewModel gps,
              _,
            ) =>
                _buildGpsSimulationCard(context, gps, office),
          ),
        ],
        const SizedBox(height: 20),
        const SectionHeader(title: 'API server address'),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _apiBaseUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'API base URL',
                    hintText: 'http://192.168.1.10:8090',
                    prefixIcon: Icon(Icons.link_outlined),
                  ),
                  onSubmitted: (_) => _saveApiBaseUrl(context, apiSettings),
                ),
                const SizedBox(height: 12),
                Text(
                  'Effective URL: ${apiSettings.baseUrl}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    FilledButton.tonal(
                      onPressed: apiSettings.isSaving
                          ? null
                          : () => _saveApiBaseUrl(context, apiSettings),
                      child: Text(
                        apiSettings.isSaving ? 'Saving…' : 'Save & retry',
                      ),
                    ),
                    TextButton(
                      onPressed: apiSettings.isSaving
                          ? null
                          : () => _resetApiBaseUrl(context, apiSettings),
                      child: const Text('Use compile-time default'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Android emulator: http://10.0.2.2:8090. Physical phone: '
                  'http://<computer-LAN-IP>:8090. Keep the phone on the same '
                  'Wi-Fi as the computer running the mock server.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Reviewer configuration'),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: InfoTile(
              icon: Icons.bug_report_outlined,
              label: 'Mock scenario',
              value: AppConfig.mockScenario,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGpsSimulationCard(
    BuildContext context,
    LocationSimulationViewModel gps,
    OfficeLocation office,
  ) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final double distance = gps.distanceFrom(office);
    final bool inside = gps.isWithinOffice(office);
    final bool configured = office.isConfigured;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: gps.simulationEnabled,
              onChanged: (bool value) => gps.setSimulationEnabled(value),
              title: const Text('Use simulated GPS'),
              subtitle: Text(
                gps.realGpsEnabled
                    ? 'Real device GPS is active (default).'
                    : 'Fixed development coordinates are active.',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _latitudeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Simulated latitude',
                prefixIcon: Icon(Icons.explore_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _longitudeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Simulated longitude',
                prefixIcon: Icon(Icons.explore_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: () => _applyCoordinates(context, gps),
                  child: const Text('Apply coordinates'),
                ),
                TextButton(
                  onPressed: configured
                      ? () => _usePreset(context, gps, office, inside: true)
                      : null,
                  child: const Text('Inside 200 m'),
                ),
                TextButton(
                  onPressed: configured
                      ? () => _usePreset(context, gps, office, inside: false)
                      : null,
                  child: const Text('Outside 200 m'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: configured && inside
                    ? colors.primaryContainer
                    : colors.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
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
            ),
            const SizedBox(height: 8),
            Text(
              'Development only. The 200 m attendance rule is unchanged and is '
              'still enforced for every simulated coordinate.',
              style: TextStyle(
                fontSize: 11,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyCoordinates(BuildContext context, LocationSimulationViewModel gps) {
    final String? error = gps.setCoordinatesFromText(
      _latitudeController.text,
      _longitudeController.text,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              'Simulated point updated. Switch on simulated GPS to use it.',
        ),
      ),
    );
  }

  void _usePreset(
    BuildContext context,
    LocationSimulationViewModel gps,
    OfficeLocation office, {
    required bool inside,
  }) {
    if (inside) {
      gps.useInsideOfficePreset(office);
    } else {
      gps.useOutsideOfficePreset(office);
    }
    _latitudeController.text = gps.simulatedPoint.latitude.toStringAsFixed(6);
    _longitudeController.text = gps.simulatedPoint.longitude.toStringAsFixed(6);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          inside
              ? 'Inside-office point selected.'
              : 'Outside-office point selected; next attendance action should be rejected.',
        ),
      ),
    );
  }

  Future<void> _saveApiBaseUrl(
    BuildContext context,
    ApiSettingsViewModel settings,
  ) async {
    final ActionResult result =
        await settings.saveBaseUrl(_apiBaseUrlController.text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    if (!result.success) return;
    _apiBaseUrlController.text = settings.baseUrl;
    await _retryAfterApiChange(context);
  }

  Future<void> _resetApiBaseUrl(
    BuildContext context,
    ApiSettingsViewModel settings,
  ) async {
    final ActionResult result = await settings.resetToDefault();
    if (!context.mounted) return;
    _apiBaseUrlController.text = settings.baseUrl;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    if (!result.success) return;
    await _retryAfterApiChange(context);
  }

  Future<void> _retryAfterApiChange(BuildContext context) async {
    await context.read<DashboardViewModel>().refresh();
    if (!context.mounted) return;
    await context.read<SyncViewModel>().syncNow(silent: true);
    if (!context.mounted) return;
    await context.read<DashboardViewModel>().reloadLocal();
  }
}
