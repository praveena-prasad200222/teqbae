import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:teqbae/models/attendance_event.dart';
import 'package:teqbae/models/attendance_event_type.dart';
import 'package:teqbae/models/sync_status.dart';
import 'package:teqbae/providers/connectivity_viewmodel.dart';
import 'package:teqbae/providers/sync_viewmodel.dart';
import 'package:teqbae/services/network/connectivity_service.dart';
import 'package:teqbae/services/sync/sync_engine.dart';
import 'package:teqbae/widgets/state_views.dart';
import 'package:teqbae/widgets/sync_status_chip.dart';

import '../helpers/fake_api_client.dart';
import '../helpers/in_memory_local_storage.dart';

void main() {
  testWidgets('pending-sync state renders Pending Sync and pending count',
      (WidgetTester tester) async {
    final InMemoryLocalStorage storage = InMemoryLocalStorage();
    await storage.putEvent(AttendanceEvent.create(
      type: AttendanceEventType.checkIn,
      timestampUtc: DateTime.utc(2026, 1, 15, 4),
      latitude: 10.000000,
      longitude: 76.000000,
      dateKey: '2026-01-15',
      sequence: 1,
    ));
    final FakeApiClient api = FakeApiClient();
    final ConnectivityViewModel connectivity =
        ConnectivityViewModel(ConnectivityService());
    final SyncViewModel sync = SyncViewModel(
      engine: SyncEngine(api: api, storage: storage),
      storage: storage,
      connectivity: connectivity,
    );
    await sync.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<SyncViewModel>.value(
          value: sync,
          child: Scaffold(
            body: Column(
              children: <Widget>[
                Consumer<SyncViewModel>(
                  builder: (BuildContext context, SyncViewModel vm, _) =>
                      Text('${vm.pendingCount} pending'),
                ),
                const SyncStatusChip(status: SyncStatus.pending),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pending Sync'), findsOneWidget);
    expect(find.text('1 pending'), findsOneWidget);
  });

  testWidgets('loading state renders a progress indicator and message',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoadingView(message: 'Loading…'))),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading…'), findsOneWidget);
  });
}
