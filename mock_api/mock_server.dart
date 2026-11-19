// Standalone local mock REST API for the REBS HRMS Flutter app.
// Run from the project root:  dart run mock_api/mock_server.dart --port=8090
// No Flutter bindings are used; this file is pure Dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:teqbae/constants/app_config.dart';
import 'package:teqbae/utils/demo_attendance_seed.dart';

const int _defaultPort = 8090;
const int _defaultOffsetMinutes = 330;

class MockConfig {
  final int port;
  final String defaultScenario;
  final int offsetMinutes;
  final double officeLat;
  final double officeLng;
  final double radius;
  final bool officeConfigured;

  /// Office values come from the single central [AppConfig]. This server never
  /// owns its own office coordinates or name.
  MockConfig.fromEnvironment()
      : port = int.fromEnvironment('PORT', defaultValue: _defaultPort),
        defaultScenario = const String.fromEnvironment(
          'SCENARIO',
          defaultValue: 'success',
        ),
        offsetMinutes = int.fromEnvironment(
          'COMPANY_TZ_OFFSET_MINUTES',
          defaultValue: _defaultOffsetMinutes,
        ),
        officeLat = AppConfig.officeLatitude,
        officeLng = AppConfig.officeLongitude,
        radius = AppConfig.officeRadiusMeters,
        officeConfigured = AppConfig.isOfficeConfigured;

  MockConfig.copyWith(MockConfig other, {int? port, String? scenario})
      : port = port ?? other.port,
        defaultScenario = scenario ?? other.defaultScenario,
        offsetMinutes = other.offsetMinutes,
        officeLat = other.officeLat,
        officeLng = other.officeLng,
        radius = other.radius,
        officeConfigured = other.officeConfigured;
}

void main(List<String> args) async {
  MockConfig config = MockConfig.fromEnvironment();
  for (final String arg in args) {
    if (arg.startsWith('--port=')) {
      final int? port = int.tryParse(arg.split('=')[1]);
      if (port != null) config = MockConfig.copyWith(config, port: port);
    } else if (arg.startsWith('--scenario=')) {
      config = MockConfig.copyWith(
        config,
        scenario: arg.split('=')[1],
      );
    }
  }

  final _MockState state = _MockState(config);
  final HttpServer server = await HttpServer.bind(
    InternetAddress.anyIPv4,
    config.port,
  );

  stdout.writeln('REBS HRMS mock API listening on http://0.0.0.0:${server.port}');
  stdout.writeln('  Android emulator base URL : http://10.0.2.2:${server.port}');
  stdout.writeln('  iOS simulator base URL    : http://localhost:${server.port}');
  stdout.writeln('  Scenario                  : ${config.defaultScenario}');
  stdout.writeln('Available scenarios: success | slow | timeout | server_error | '
      'conflict | leave_rejected');

  await for (final HttpRequest request in server) {
    unawaited(_handle(request, state, config));
  }
}

Future<void> _handle(
  HttpRequest request,
  _MockState state,
  MockConfig config,
) async {
  final String path = request.uri.path;
  final String method = request.method;
  final String scenario = request.headers.value('X-Mock-Scenario') ??
      config.defaultScenario;

  try {
    if (method == 'GET' && path == '/employee/me') {
      await _sendJson(request.response, 200, state.employee);
      return;
    }

    if (method == 'GET' && path == '/attendance') {
      await _sendJson(request.response, 200, <String, dynamic>{
        'records': state.recordsForMonth(request.uri.queryParameters['month']),
      });
      return;
    }

    if (method == 'POST' && path == '/attendance/events') {
      await _handleAttendanceEvent(request, state, scenario);
      return;
    }

    if (method == 'GET' && path == '/leave/balance') {
      await _sendJson(request.response, 200, state.balance);
      return;
    }

    if (method == 'GET' && path == '/leave/requests') {
      await _sendJson(request.response, 200, <String, dynamic>{
        'requests': state.leaveRequests,
      });
      return;
    }

    if (method == 'POST' && path == '/leave/requests') {
      await _handleLeaveRequest(request, state, scenario);
      return;
    }

    await _sendJson(request.response, 404, <String, dynamic>{
      'message': 'No mock endpoint for $method $path',
    });
  } catch (error) {
    await _sendJson(request.response, 500, <String, dynamic>{
      'message': 'Mock server error: $error',
    });
  }
}

Future<void> _handleAttendanceEvent(
  HttpRequest request,
  _MockState state,
  String scenario,
) async {
  if (scenario == 'timeout') {
    // Intentionally never answer quickly: the client times out locally while
    // the "server" may already have accepted the event in a real backend.
    await Future<void>.delayed(const Duration(seconds: 30));
  }
  if (scenario == 'slow') {
    await Future<void>.delayed(const Duration(seconds: 4));
  }
  if (scenario == 'server_error') {
    await _sendJson(request.response, 500, <String, dynamic>{
      'message': 'Mock server error (scenario=server_error).',
    });
    return;
  }
  if (scenario == 'conflict') {
    await _sendJson(request.response, 409, <String, dynamic>{
      'message': 'Attendance already exists for this date (scenario=conflict).',
    });
    return;
  }

  final Map<String, dynamic> body = await _readBody(request);
  final String? eventId = body['eventId'] as String?;
  if (eventId == null || eventId.isEmpty) {
    await _sendJson(request.response, 422, <String, dynamic>{
      'message': 'eventId is required.',
    });
    return;
  }

  // Idempotency: a retry with the SAME eventId returns the original receipt.
  final String? existingServerId = state.processedEventIds[eventId];
  if (existingServerId != null) {
    await _sendJson(request.response, 200, <String, dynamic>{
      'eventId': eventId,
      'serverId': existingServerId,
      'duplicate': true,
    });
    return;
  }

  final String type = (body['type'] as String?) ?? 'check_in';
  final double latitude = (body['latitude'] as num?)?.toDouble() ?? 0;
  final double longitude = (body['longitude'] as num?)?.toDouble() ?? 0;
  if (!state.config.officeConfigured) {
    await _sendJson(request.response, 422, <String, dynamic>{
      'message': 'Teqbae office coordinates are not configured. '
          '${AppConfig.officeConfigurationHint}',
    });
    return;
  }

  final double distance = _haversine(
    state.officeLat,
    state.officeLng,
    latitude,
    longitude,
  );
  if (distance > state.radius) {
    await _sendJson(request.response, 422, <String, dynamic>{
      'message': 'Outside office geofence: ${distance.round()} m from office.',
    });
    return;
  }

  final String dateKey = (body['dateKey'] as String?) ?? '';
  final List<Map<String, dynamic>> dayEvents = state.events
      .where((Map<String, dynamic> e) => e['dateKey'] == dateKey)
      .toList();

  if (type == 'check_in' &&
      dayEvents.any((Map<String, dynamic> e) => e['type'] == 'check_in')) {
    await _sendJson(request.response, 409, <String, dynamic>{
      'message': 'Attendance already exists for $dateKey.',
    });
    return;
  }
  if (type == 'check_out') {
    if (!dayEvents
        .any((Map<String, dynamic> e) => e['type'] == 'check_in')) {
      await _sendJson(request.response, 422, <String, dynamic>{
        'message': 'Check-out requires a check-in first.',
      });
      return;
    }
    if (dayEvents
        .any((Map<String, dynamic> e) => e['type'] == 'check_out')) {
      await _sendJson(request.response, 409, <String, dynamic>{
        'message': 'Check-out already recorded for $dateKey.',
      });
      return;
    }
  }

  final String serverId = 'SRV-${state.nextServerId++}';
  state.processedEventIds[eventId] = serverId;
  state.events.add(body);
  await _sendJson(request.response, 201, <String, dynamic>{
    'eventId': eventId,
    'serverId': serverId,
    'duplicate': false,
  });
}

Future<void> _handleLeaveRequest(
  HttpRequest request,
  _MockState state,
  String scenario,
) async {
  if (scenario == 'server_error') {
    await _sendJson(request.response, 500, <String, dynamic>{
      'message': 'Mock server error (scenario=server_error).',
    });
    return;
  }
  if (scenario == 'leave_rejected') {
    await _sendJson(request.response, 422, <String, dynamic>{
      'message': 'Server rejected the leave request: manager approval quota exceeded.',
    });
    return;
  }

  final Map<String, dynamic> body = await _readBody(request);
  final String start = (body['startDate'] as String?) ?? '';
  final String end = (body['endDate'] as String?) ?? '';
  final String type = (body['type'] as String?) ?? 'casual';
  final int days = (body['days'] as num?)?.toInt() ?? 0;
  final String reason = (body['reason'] as String?) ?? '';

  if (reason.replaceAll(RegExp(r'\s'), '').length < 10) {
    await _sendJson(request.response, 422, <String, dynamic>{
      'message': 'Server validation: reason must contain at least 10 non-whitespace characters.',
    });
    return;
  }

  final bool overlap = state.leaveRequests.any((Map<String, dynamic> r) {
    if (r['status'] == 'rejected') return false;
    return start.compareTo(r['endDate'] as String) <= 0 &&
        end.compareTo(r['startDate'] as String) >= 0;
  });
  if (overlap) {
    await _sendJson(request.response, 422, <String, dynamic>{
      'message': 'Server validation: dates overlap an existing leave request.',
    });
    return;
  }

  final int balance = (state.balance[type] as num?)?.toInt() ?? 0;
  if (days > balance) {
    await _sendJson(request.response, 422, <String, dynamic>{
      'message': 'Server validation: requested days exceed the $type balance.',
    });
    return;
  }

  // Idempotency: an offline request keeps its client id. A retry (or a sync
  // after reconnect) must return the original receipt instead of inserting a
  // second leave request.
  final String? clientId = (body['id'] as String?) ??
      (body['requestId'] as String?);
  if (clientId != null && clientId.isNotEmpty) {
    final Map<String, dynamic>? receipt =
        state.leaveReceiptsById[clientId];
    if (receipt != null) {
      await _sendJson(request.response, 200, receipt);
      return;
    }
  }

  final String serverId = clientId != null && clientId.isNotEmpty
      ? clientId
      : 'LRV-${state.nextLeaveId++}';
  final Map<String, dynamic> created = <String, dynamic>{
    'id': serverId,
    'type': type,
    'startDate': start,
    'endDate': end,
    'reason': reason,
    'days': days,
    'status': 'pending',
    'submittedAtUtc': DateTime.now().toUtc().toIso8601String(),
  };
  state.leaveRequests.insert(0, created);
  if (clientId != null && clientId.isNotEmpty) {
    state.leaveReceiptsById[clientId] = created;
  }
  await _sendJson(request.response, 201, created);
}

Future<Map<String, dynamic>> _readBody(HttpRequest request) async {
  final List<int> bytes = await request.fold<List<int>>(
    <int>[],
    (List<int> previous, List<int> element) => previous..addAll(element),
  );
  final String raw = utf8.decode(bytes);
  if (raw.isEmpty) return <String, dynamic>{};
  final dynamic decoded = jsonDecode(raw);
  return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
}

Future<void> _sendJson(HttpResponse response, int status, Object body) async {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

double _haversine(double lat1, double lng1, double lat2, double lng2) {
  const double radius = 6371000;
  double radians(double value) => value * math.pi / 180;
  final double dLat = radians(lat2 - lat1);
  final double dLng = radians(lng2 - lng1);
  final double a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(radians(lat1)) *
          math.cos(radians(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

class _MockState {
  final MockConfig config;
  late final double officeLat = config.officeLat;
  late final double officeLng = config.officeLng;
  late final double radius = config.radius;
  int nextServerId = 1;
  int nextLeaveId = 1;
  final Map<String, String> processedEventIds = <String, String>{};
  final Map<String, Map<String, dynamic>> leaveReceiptsById =
      <String, Map<String, dynamic>>{};
  final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> leaveRequests = <Map<String, dynamic>>[];
  final Map<String, dynamic> balance = <String, dynamic>{
    'casual': 12,
    'sick': 6,
  };

  _MockState(this.config) {
    _seed();
  }

  Map<String, dynamic> get employee => <String, dynamic>{
        'id': 'EMP-1001',
        'name': 'Aarav Sharma',
        'department': 'Human Resources',
        'designation': 'HR Executive',
        'email': 'aarav.sharma@rebs.example',
        'office': <String, dynamic>{
          'name': AppConfig.officeName,
          'latitude': config.officeLat,
          'longitude': config.officeLng,
          'radiusMeters': config.radius,
          'timezoneOffsetMinutes': config.offsetMinutes,
          'isConfigured': config.officeConfigured,
        },
      };

  void _seed() {
    // Five complete days both here and in the app's local cache, so UI and API
    // show the same "latest five" history even before the API is reachable.
    events.addAll(
      DemoAttendanceSeed.eventJson(offsetMinutes: config.offsetMinutes),
    );

    final DateTime companyNowLocal = DateTime.now().toUtc()
        .add(Duration(minutes: config.offsetMinutes));
    final String tomorrow = _key(companyNowLocal.add(const Duration(days: 1)));
    final String nextWeek = _key(companyNowLocal.add(const Duration(days: 7)));
    final String nextWeekPlusTwo =
        _key(companyNowLocal.add(const Duration(days: 9)));

    leaveRequests.addAll(<Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'LRV-1001',
        'type': 'casual',
        'startDate': tomorrow,
        'endDate': tomorrow,
        'reason': 'Family function at home.',
        'days': 1,
        'status': 'pending',
        'submittedAtUtc': DateTime.now().toUtc().toIso8601String(),
      },
      <String, dynamic>{
        'id': 'LRV-1002',
        'type': 'sick',
        'startDate': nextWeek,
        'endDate': nextWeekPlusTwo,
        'reason': 'Medical appointment and recovery.',
        'days': 3,
        'status': 'approved',
        'submittedAtUtc': DateTime.now().toUtc().toIso8601String(),
      },
      <String, dynamic>{
        'id': 'LRV-1000',
        'type': 'casual',
        'startDate': _key(companyNowLocal.subtract(const Duration(days: 12))),
        'endDate': _key(companyNowLocal.subtract(const Duration(days: 11))),
        'reason': 'Personal work pending earlier.',
        'days': 2,
        'status': 'rejected',
        'submittedAtUtc': DateTime.now().toUtc().toIso8601String(),
      },
    ]);
  }

  List<Map<String, dynamic>> recordsForMonth(String? month) {
    final Map<String, Map<String, dynamic>> byDay =
        <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic> event in events) {
      final String key = event['dateKey'] as String;
      if (month != null && !key.startsWith(month)) continue;
      final Map<String, dynamic> record =
          byDay.putIfAbsent(key, () => <String, dynamic>{
                'dateKey': key,
                'checkIn': null,
                'checkOut': null,
              });
      if (event['type'] == 'check_in' && record['checkIn'] == null) {
        record['checkIn'] = event;
      } else if (event['type'] == 'check_out' && record['checkOut'] == null) {
        record['checkOut'] = event;
      }
    }
    final List<Map<String, dynamic>> records = byDay.values.toList()
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
          (b['dateKey'] as String).compareTo(a['dateKey'] as String));
    return records.take(50).toList();
  }

  String _key(DateTime companyLocal) =>
      '${companyLocal.year.toString().padLeft(4, '0')}-'
      '${companyLocal.month.toString().padLeft(2, '0')}-'
      '${companyLocal.day.toString().padLeft(2, '0')}';
}
