import 'dart:convert';

import 'package:hive/hive.dart';

import '../../constants/app_config.dart';
import '../../constants/cache_keys.dart';
import '../../models/attendance_event.dart';
import '../../models/attendance_record.dart';
import '../../models/employee.dart';
import '../../models/leave_balance.dart';
import '../../models/leave_request.dart';
import '../../utils/demo_attendance_seed.dart';
import 'local_storage.dart';

/// Hive-backed storage. Values are stored as JSON strings so no code
/// generation / TypeAdapter registration is required.
class HiveLocalStorage implements LocalStorage {
  late final Box<String> _events;
  late final Box<String> _cache;

  HiveLocalStorage();

  @override
  Future<void> init() async {
    if (!Hive.isBoxOpen(AppConfig.eventsBox)) {
      await Hive.openBox<String>(AppConfig.eventsBox);
    }
    if (!Hive.isBoxOpen(AppConfig.cacheBox)) {
      await Hive.openBox<String>(AppConfig.cacheBox);
    }
    _events = Hive.box<String>(AppConfig.eventsBox);
    _cache = Hive.box<String>(AppConfig.cacheBox);

    // A fresh install (or an earlier failed fetch that cached an empty list)
    // still shows the required latest-five demo history. Once the API is
    // reachable these records are replaced by the server response.
    if ((await getCachedRemoteRecords()).isEmpty) {
      await putCachedRemoteRecords(DemoAttendanceSeed.records());
    }
  }

  @override
  Future<List<AttendanceEvent>> getEvents() async {
    final List<AttendanceEvent> events = _events.values
        .map((String value) =>
            AttendanceEvent.fromJson(jsonDecode(value) as Map<String, dynamic>))
        .toList();
    events.sort((AttendanceEvent a, AttendanceEvent b) =>
        a.sequence.compareTo(b.sequence));
    return events;
  }

  @override
  Future<AttendanceEvent?> getEvent(String eventId) async {
    final String? raw = _events.get(eventId);
    if (raw == null) return null;
    return AttendanceEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> putEvent(AttendanceEvent event) =>
      _events.put(event.eventId, jsonEncode(event.toJson()));

  @override
  Future<void> deleteEvent(String eventId) => _events.delete(eventId);

  @override
  Future<List<AttendanceRecord>> getCachedRemoteRecords() async {
    final String? raw = _cache.get(CacheKeys.remoteAttendanceRecords);
    if (raw == null) return <AttendanceRecord>[];
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) return <AttendanceRecord>[];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> json) => AttendanceRecord.fromJson(json))
        .toList();
  }

  @override
  Future<void> putCachedRemoteRecords(List<AttendanceRecord> records) =>
      _cache.put(
        CacheKeys.remoteAttendanceRecords,
        jsonEncode(records.map((AttendanceRecord r) => r.toJson()).toList()),
      );

  @override
  Future<Employee?> getEmployee() => _readJson(
        CacheKeys.employee,
        (Map<String, dynamic> json) => Employee.fromJson(json),
      );

  @override
  Future<void> putEmployee(Employee employee) =>
      _cache.put(CacheKeys.employee, jsonEncode(employee.toJson()));

  @override
  Future<LeaveBalance?> getLeaveBalance() => _readJson(
        CacheKeys.leaveBalance,
        (Map<String, dynamic> json) => LeaveBalance.fromJson(json),
      );

  @override
  Future<void> putLeaveBalance(LeaveBalance balance) =>
      _cache.put(CacheKeys.leaveBalance, jsonEncode(balance.toJson()));

  @override
  Future<List<LeaveRequest>> getLeaveRequests() async {
    final String? raw = _cache.get(CacheKeys.leaveRequests);
    if (raw == null) return <LeaveRequest>[];
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) return <LeaveRequest>[];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> json) => LeaveRequest.fromJson(json))
        .toList();
  }

  @override
  Future<void> putLeaveRequests(List<LeaveRequest> requests) => _cache.put(
        CacheKeys.leaveRequests,
        jsonEncode(requests.map((LeaveRequest r) => r.toJson()).toList()),
      );

  @override
  Future<DateTime?> getLastSuccessfulSync() async {
    final String? raw = _cache.get(CacheKeys.lastSuccessfulSync);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  @override
  Future<void> setLastSuccessfulSync(DateTime timestamp) =>
      _cache.put(CacheKeys.lastSuccessfulSync, timestamp.toIso8601String());

  @override
  Future<String?> getApiBaseUrl() async => _cache.get(CacheKeys.apiBaseUrl);

  @override
  Future<void> setApiBaseUrl(String baseUrl) =>
      _cache.put(CacheKeys.apiBaseUrl, baseUrl);

  @override
  Future<({double latitude, double longitude})?> getOfficeCoordinates() async {
    final String? latitudeText = _cache.get(CacheKeys.officeLatitude);
    final String? longitudeText = _cache.get(CacheKeys.officeLongitude);
    if (latitudeText == null || longitudeText == null) return null;
    final double? latitude = double.tryParse(latitudeText);
    final double? longitude = double.tryParse(longitudeText);
    if (latitude == null || longitude == null) return null;
    return (latitude: latitude, longitude: longitude);
  }

  @override
  Future<void> setOfficeCoordinates(double latitude, double longitude) async {
    await _cache.put(CacheKeys.officeLatitude, latitude.toString());
    await _cache.put(CacheKeys.officeLongitude, longitude.toString());
  }

  Future<T?> _readJson<T>(
    String key,
    T Function(Map<String, dynamic> json) decoder,
  ) async {
    final String? raw = _cache.get(key);
    if (raw == null) return null;
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return decoder(decoded);
  }
}
