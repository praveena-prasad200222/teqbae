import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/attendance_record.dart';
import '../models/employee.dart';
import '../models/leave_balance.dart';
import '../repositories/attendance_repository.dart';
import '../repositories/employee_repository.dart';
import '../repositories/leave_repository.dart';
import '../utils/attendance_merge.dart';
import '../utils/company_clock.dart';
import 'connectivity_viewmodel.dart';
import 'view_state.dart';

/// MVVM ViewModel for the dashboard screen.
///
/// Local data is published first and network work runs in one deduplicated
/// background task. A slow/offline API therefore can never keep the spinner on
/// screen, and concurrent callers share the same Future.
class DashboardViewModel extends ChangeNotifier {
  final EmployeeRepository employeeRepository;
  final AttendanceRepository attendanceRepository;
  final LeaveRepository leaveRepository;
  final ConnectivityViewModel connectivity;
  final CompanyClock clock;

  DashboardViewModel({
    required this.employeeRepository,
    required this.attendanceRepository,
    required this.leaveRepository,
    required this.connectivity,
    required this.clock,
  }) {
    connectivity.addListener(_onConnectivityChanged);
  }

  ViewState _state = ViewState.initial;
  String? _errorMessage;
  String? _refreshError;
  Employee? _employee;
  LeaveBalance? _balance;
  List<AttendanceRecord> _records = <AttendanceRecord>[];
  bool _isRefreshing = false;
  Future<void>? _refreshFuture;

  ViewState get state => _state;
  String? get errorMessage => _errorMessage;
  String? get refreshError => _refreshError;
  Employee? get employee => _employee;
  LeaveBalance? get balance => _balance;
  List<AttendanceRecord> get records =>
      List<AttendanceRecord>.unmodifiable(_records);
  List<AttendanceRecord> get latestRecords =>
      List<AttendanceRecord>.unmodifiable(_records.take(5).toList());
  bool get isOffline => connectivity.isOffline;
  bool get isRefreshing => _isRefreshing;

  AttendanceRecord? get todayRecord {
    final String key = clock.todayKey;
    for (final AttendanceRecord record in _records) {
      if (record.dateKey == key) return record;
    }
    return null;
  }

  /// First load: publish the cache, then refresh once when online.
  Future<void> load() => _beginRefresh();

  /// Pull-to-refresh / Retry. Also deduplicated while a refresh is running.
  Future<void> refresh() => _beginRefresh();

  /// Re-reads cached records after a local Check In / Check Out or after a sync
  /// attempt changed their upload status. This keeps the dashboard in step
  /// with the Attendance screen without waiting for a restart or a full
  /// network refresh.
  Future<void> reloadLocal() async {
    try {
      await _reloadCachedRecords();
      final LeaveBalance? cachedBalance =
          await leaveRepository.getCachedBalance();
      if (cachedBalance != null) _balance = cachedBalance;
      if (_state == ViewState.initial || _state == ViewState.loading) {
        _state = ViewState.ready;
      }
      notifyListeners();
    } catch (error) {
      // A cache read must never break the action that triggered it.
      debugPrint('Dashboard local reload failed: $error');
    }
  }

  Future<void> _beginRefresh() {
    final Future<void>? pending = _refreshFuture;
    if (pending != null) return pending;

    final Completer<void> completer = Completer<void>();
    _refreshFuture = completer.future;
    unawaited(_loadCacheThenRefresh(completer));
    return completer.future;
  }

  Future<void> _loadCacheThenRefresh(Completer<void> completer) async {
    _refreshError = null;
    try {
      await _loadCache();
    } catch (error) {
      _errorMessage = error.toString();
      _state = ViewState.error;
      _finish(completer);
      return;
    }

    if (connectivity.isOffline) {
      _refreshError = 'Offline — showing locally saved dashboard data.';
      _finish(completer);
      return;
    }

    final List<Object> errors = await _fetchRemote();
    if (errors.isNotEmpty) {
      _refreshError =
          '${errors.first} Showing locally saved data. You can retry below.';
    } else {
      _refreshError = null;
    }
    _finish(completer);
  }

  Future<void> _loadCache() async {
    _employee ??= await employeeRepository.getCached() ?? Employee.fallback();
    _balance ??= await leaveRepository.getCachedBalance() ?? LeaveBalance.sample;
    await _reloadCachedRecords();
    _state = ViewState.ready;
    notifyListeners();
  }

  Future<List<Object>> _fetchRemote() async {
    _isRefreshing = true;
    notifyListeners();

    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _attempt(() async {
        _employee = await employeeRepository.fetchAndCache();
      }),
      _attempt(_refreshAttendance),
      _attempt(() async {
        _balance = await leaveRepository.fetchBalance();
      }),
    ]);
    return results.whereType<Object>().toList();
  }

  Future<void> _refreshAttendance() async {
    final List<AttendanceRecord> remote =
        await attendanceRepository.fetchMonth(clock.currentMonthKey);
    await attendanceRepository.cacheRemoteRecords(remote);
    await _reloadCachedRecords();
  }

  Future<void> _reloadCachedRecords() async {
    final List<AttendanceRecord> remote =
        await attendanceRepository.getCachedRemoteRecords();
    final List<AttendanceRecord> local =
        await attendanceRepository.getCachedRecords();
    _records = AttendanceMerge.combine(remote, local);
  }

  Future<Object?> _attempt(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } catch (error) {
      return error;
    }
  }

  void _finish(Completer<void> completer) {
    _isRefreshing = false;
    if (identical(_refreshFuture, completer.future)) _refreshFuture = null;
    if (!completer.isCompleted) completer.complete();
    notifyListeners();
  }

  void _onConnectivityChanged() {
    if (connectivity.isOnline) unawaited(refresh());
  }

  @override
  void dispose() {
    connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}
