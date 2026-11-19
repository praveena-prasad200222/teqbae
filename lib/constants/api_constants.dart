class ApiEndpoints {
  ApiEndpoints._();

  static const String employeeMe = '/employee/me';
  static const String attendance = '/attendance';
  static const String attendanceEvents = '/attendance/events';
  static const String leaveBalance = '/leave/balance';
  static const String leaveRequests = '/leave/requests';

  static String leaveRequest(String id) =>
      '/leave/requests/${Uri.encodeComponent(id)}';
}
