import 'package:teqbae/models/attendance_event.dart';
import 'package:teqbae/models/attendance_record.dart';
import 'package:teqbae/models/employee.dart';
import 'package:teqbae/models/leave_balance.dart';
import 'package:teqbae/models/leave_request.dart';
import 'package:teqbae/services/storage/local_storage.dart';

/// Deterministic storage used by unit/widget tests (no Hive, no filesystem).
class InMemoryLocalStorage implements LocalStorage {
  final Map<String, AttendanceEvent> events = <String, AttendanceEvent>{};
  final List<AttendanceRecord> remoteRecords = <AttendanceRecord>[];
  Employee? employee;
  LeaveBalance? balance;
  List<LeaveRequest> requests = <LeaveRequest>[];
  DateTime? lastSync;
  String? apiBaseUrl;
  ({double latitude, double longitude})? officeCoordinates;

  @override
  Future<void> init() async {}

  @override
  Future<List<AttendanceEvent>> getEvents() async {
    final List<AttendanceEvent> result = events.values.toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    return result;
  }

  @override
  Future<AttendanceEvent?> getEvent(String eventId) async => events[eventId];

  @override
  Future<void> putEvent(AttendanceEvent event) async =>
      events[event.eventId] = event;

  @override
  Future<void> deleteEvent(String eventId) async => events.remove(eventId);

  @override
  Future<List<AttendanceRecord>> getCachedRemoteRecords() async =>
      List<AttendanceRecord>.from(remoteRecords);

  @override
  Future<void> putCachedRemoteRecords(List<AttendanceRecord> records) async {
    remoteRecords
      ..clear()
      ..addAll(records);
  }

  @override
  Future<Employee?> getEmployee() async => employee;

  @override
  Future<void> putEmployee(Employee value) async => employee = value;

  @override
  Future<LeaveBalance?> getLeaveBalance() async => balance;

  @override
  Future<void> putLeaveBalance(LeaveBalance value) async => balance = value;

  @override
  Future<List<LeaveRequest>> getLeaveRequests() async =>
      List<LeaveRequest>.from(requests);

  @override
  Future<void> putLeaveRequests(List<LeaveRequest> value) async =>
      requests = List<LeaveRequest>.from(value);

  @override
  Future<DateTime?> getLastSuccessfulSync() async => lastSync;

  @override
  Future<void> setLastSuccessfulSync(DateTime timestamp) async =>
      lastSync = timestamp;

  @override
  Future<String?> getApiBaseUrl() async => apiBaseUrl;

  @override
  Future<void> setApiBaseUrl(String value) async => apiBaseUrl = value;

  @override
  Future<({double latitude, double longitude})?> getOfficeCoordinates() async =>
      officeCoordinates;

  @override
  Future<void> setOfficeCoordinates(double latitude, double longitude) async =>
      officeCoordinates = (latitude: latitude, longitude: longitude);
}
