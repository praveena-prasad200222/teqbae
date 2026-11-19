import 'package:teqbae/models/attendance_event.dart';
import 'package:teqbae/models/attendance_event_type.dart';
import 'package:teqbae/models/attendance_record.dart';
import 'package:teqbae/models/employee.dart';
import 'package:teqbae/models/leave_balance.dart';
import 'package:teqbae/models/leave_request.dart';
import 'package:teqbae/models/leave_request_status.dart';
import 'package:teqbae/models/leave_type.dart';
import 'package:teqbae/services/api/api_client.dart';

class FakeApiClient extends ApiClient {
  FakeApiClient() : super(baseUrl: 'http://localhost');

  final List<AttendanceEvent> submittedEvents = <AttendanceEvent>[];
  final Map<String, String> serverIdsByEvent = <String, String>{};
  Object? attendanceError;
  Object? leaveError;
  Object? leaveDeleteError;
  final List<Map<String, Object?>> submittedLeaveRequests =
      <Map<String, Object?>>[];
  final List<String> deletedLeaveRequestIds = <String>[];

  Employee employee = Employee.fallback();
  LeaveBalance leaveBalance = const LeaveBalance(casual: 12, sick: 6);
  List<LeaveRequest> leaveRequests = <LeaveRequest>[];
  List<AttendanceRecord> attendanceRecords = <AttendanceRecord>[];

  @override
  Future<Employee> fetchEmployee() async => employee;

  @override
  Future<List<AttendanceRecord>> fetchAttendance(String monthKey) async =>
      attendanceRecords;

  @override
  Future<AttendanceSubmissionResult> submitAttendanceEvent(
    AttendanceEvent event,
  ) async {
    if (attendanceError != null) throw attendanceError!;
    submittedEvents.add(event);
    final String serverId = serverIdsByEvent.putIfAbsent(
      event.eventId,
      () => 'SRV-${serverIdsByEvent.length + 1}',
    );
    return AttendanceSubmissionResult(
      eventId: event.eventId,
      serverId: serverId,
      duplicate: submittedEvents.length > serverIdsByEvent.length,
    );
  }

  @override
  Future<LeaveBalance> fetchLeaveBalance() async => leaveBalance;

  @override
  Future<List<LeaveRequest>> fetchLeaveRequests() async => leaveRequests;

  @override
  Future<LeaveRequest> submitLeaveRequest({
    required LeaveType type,
    required String startDate,
    required String endDate,
    required String reason,
    required int days,
    required String requestId,
  }) async {
    submittedLeaveRequests.add(<String, Object?>{
      'requestId': requestId,
      'startDate': startDate,
      'endDate': endDate,
    });
    if (leaveError != null) throw leaveError!;
    return LeaveRequest(
      id: requestId,
      type: type,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      days: days,
      status: LeaveRequestStatus.pending,
      submittedAtUtc: DateTime.utc(2026, 1, 15),
    );
  }

  @override
  Future<void> deleteLeaveRequest(String requestId) async {
    if (leaveDeleteError != null) throw leaveDeleteError!;
    deletedLeaveRequestIds.add(requestId);
  }

  @override
  Future<void> approveLeaveRequest(String requestId) async {}
}
