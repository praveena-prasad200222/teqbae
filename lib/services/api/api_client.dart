import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../constants/api_constants.dart';
import '../../constants/app_config.dart';
import '../../models/attendance_event.dart';
import '../../models/attendance_event_type.dart';
import '../../models/attendance_record.dart';
import '../../models/employee.dart';
import '../../models/leave_balance.dart';
import '../../models/leave_request.dart';
import '../../models/leave_type.dart';
import 'api_exceptions.dart';

/// The only component that talks to the mock REST API.
/// Widgets never access hardcoded data or an HTTP client directly.
class ApiClient {
  final http.Client _client;
  String _baseUrl;
  final Duration timeout;
  final String scenario;

  ApiClient({
    http.Client? client,
    String? baseUrl,
    Duration? timeout,
    String? scenario,
  })  : _client = client ?? http.Client(),
        _baseUrl = normalizeBaseUrl(baseUrl ?? AppConfig.apiBaseUrl),
        timeout = timeout ?? AppConfig.apiTimeout,
        scenario = scenario ?? AppConfig.mockScenario;

  /// The effective URL used by every request. It can be changed at runtime
  /// from Profile → API server address without rebuilding the app.
  String get baseUrl => _baseUrl;

  /// Every repository shares one ApiClient, so updating this value immediately
  /// redirects dashboard, attendance, leave and sync requests.
  void setBaseUrl(String value) {
    _baseUrl = normalizeBaseUrl(value);
  }

  static String normalizeBaseUrl(String value) =>
      value.trim().replaceAll(RegExp(r'/+$'), '');

  /// Returns null when [value] is a usable API base URL.
  static String? validateBaseUrl(String value) {
    final String candidate = value.trim();
    if (candidate.isEmpty) return 'Enter the API base URL.';
    final Uri? uri = Uri.tryParse(candidate);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      return 'Use a full URL such as http://192.168.1.10:8090.';
    }
    if (uri.port != 0 && (uri.port < 1 || uri.port > 65535)) {
      return 'The port must be between 1 and 65535.';
    }
    return null;
  }

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Employee-Id': AppConfig.employeeId,
        'X-Mock-Scenario': scenario,
      };

  Future<Employee> fetchEmployee() async {
    final dynamic body = await _get(ApiEndpoints.employeeMe);
    return Employee.fromJson(body as Map<String, dynamic>);
  }

  Future<List<AttendanceRecord>> fetchAttendance(String monthKey) async {
    final dynamic body = await _get(
      ApiEndpoints.attendance,
      query: <String, String>{'month': monthKey},
    );
    final dynamic records = (body as Map<String, dynamic>)['records'];
    if (records is! List<dynamic>) return <AttendanceRecord>[];
    return records
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> json) => AttendanceRecord.fromJson(json))
        .toList();
  }

  Future<AttendanceSubmissionResult> submitAttendanceEvent(
    AttendanceEvent event,
  ) async {
    final dynamic body =
        await _post(ApiEndpoints.attendanceEvents, event.toJson());
    return AttendanceSubmissionResult.fromJson(body as Map<String, dynamic>);
  }

  Future<LeaveBalance> fetchLeaveBalance() async {
    final dynamic body = await _get(ApiEndpoints.leaveBalance);
    return LeaveBalance.fromJson(body as Map<String, dynamic>);
  }

  Future<List<LeaveRequest>> fetchLeaveRequests() async {
    final dynamic body = await _get(ApiEndpoints.leaveRequests);
    final dynamic requests = (body as Map<String, dynamic>)['requests'];
    if (requests is! List<dynamic>) return <LeaveRequest>[];
    return requests
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> json) => LeaveRequest.fromJson(json))
        .toList();
  }

  Future<LeaveRequest> submitLeaveRequest({
    required LeaveType type,
    required String startDate,
    required String endDate,
    required String reason,
    required int days,
    required String requestId,
  }) async {
    final dynamic body = await _post(
      ApiEndpoints.leaveRequests,
      <String, dynamic>{
        'id': requestId,
        'employeeId': AppConfig.employeeId,
        'type': type.jsonValue,
        'startDate': startDate,
        'endDate': endDate,
        'reason': reason,
        'days': days,
      },
    );
    return LeaveRequest.fromJson(body as Map<String, dynamic>);
  }

  /// Deletes a request by its stable client id. The mock server treats an
  /// unknown id as already deleted, so retries are safe.
  Future<void> deleteLeaveRequest(String requestId) async {
    await _delete(ApiEndpoints.leaveRequest(requestId));
  }

  /// Approves a leave request on the mock server.
  Future<void> approveLeaveRequest(String requestId) async {
    await _post('/leave/requests/$requestId/approve', <String, dynamic>{});
  }

  Future<dynamic> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    final Uri uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query,
    );
    return _execute(() => _client.get(uri, headers: _headers));
  }

  Future<dynamic> _post(String path, Object body) async {
    final Uri uri = Uri.parse('$baseUrl$path');
    return _execute(
      () => _client.post(
        uri,
        headers: _headers,
        body: jsonEncode(body),
      ),
    );
  }

  Future<dynamic> _delete(String path) async {
    final Uri uri = Uri.parse('$baseUrl$path');
    return _execute(() => _client.delete(uri, headers: _headers));
  }

  Future<dynamic> _execute(Future<http.Response> Function() send) async {
    late final http.Response response;
    try {
      response = await send().timeout(timeout);
    } on TimeoutException {
      throw ApiNetworkException(_reachabilityMessage());
    } on SocketException {
      throw ApiNetworkException(_reachabilityMessage());
    } on http.ClientException catch (error) {
      throw ApiNetworkException(
        'Network error while contacting $baseUrl: ${error.message}. '
        '${_addressHint()}',
      );
    }

    return _decode(response);
  }

  String _reachabilityMessage() =>
      'Cannot reach $baseUrl within ${timeout.inSeconds}s. '
      '${_addressHint()} Your local data is kept and will be retried.';

  String _addressHint() =>
      'Check that the mock server is running. On a physical phone, open '
      'Profile → API server address and use http://<computer-LAN-IP>:8090 '
      '(10.0.2.2 works only in the Android emulator).';

  dynamic _decode(http.Response response) {
    final int status = response.statusCode;
    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
    }

    if (status >= 200 && status < 300) return decoded;

    String message = 'Request failed with status $status.';
    if (decoded is Map<String, dynamic>) {
      final dynamic value = decoded['message'] ?? decoded['error'];
      if (value is String && value.isNotEmpty) message = value;
    }

    if (status == 409) throw ApiConflictException(message);
    if (status == 422) throw ApiValidationException(message);
    if (status >= 500) throw ApiServerException(message);
    throw ApiException(message, statusCode: status);
  }
}
