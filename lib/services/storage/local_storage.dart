import '../../models/attendance_event.dart';
import '../../models/attendance_record.dart';
import '../../models/employee.dart';
import '../../models/leave_balance.dart';
import '../../models/leave_request.dart';

/// Persistence contract. Hive implements it in the app; tests use an
/// in-memory implementation so business rules can be tested without Flutter.
abstract class LocalStorage {
  Future<void> init();

  Future<List<AttendanceEvent>> getEvents();

  Future<AttendanceEvent?> getEvent(String eventId);

  Future<void> putEvent(AttendanceEvent event);

  Future<void> deleteEvent(String eventId);

  Future<List<AttendanceRecord>> getCachedRemoteRecords();

  Future<void> putCachedRemoteRecords(List<AttendanceRecord> records);

  Future<Employee?> getEmployee();

  Future<void> putEmployee(Employee employee);

  Future<LeaveBalance?> getLeaveBalance();

  Future<void> putLeaveBalance(LeaveBalance balance);

  Future<List<LeaveRequest>> getLeaveRequests();

  Future<void> putLeaveRequests(List<LeaveRequest> requests);

  Future<DateTime?> getLastSuccessfulSync();

  Future<void> setLastSuccessfulSync(DateTime timestamp);

  /// Saved runtime API base URL override. Null means use AppConfig's default.
  Future<String?> getApiBaseUrl();

  Future<void> setApiBaseUrl(String baseUrl);

  /// Optional runtime office coordinates supplied by a reviewer/device.
  Future<({double latitude, double longitude})?> getOfficeCoordinates();

  Future<void> setOfficeCoordinates(double latitude, double longitude);
}
