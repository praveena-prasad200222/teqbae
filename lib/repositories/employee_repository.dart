import '../models/employee.dart';
import '../services/api/api_client.dart';
import '../services/storage/local_storage.dart';

/// Employee data with a cached-first read path for offline viewing.
class EmployeeRepository {
  final ApiClient api;
  final LocalStorage storage;

  EmployeeRepository({required this.api, required this.storage});

  Future<Employee?> getCached() => storage.getEmployee();

  Future<Employee> fetchAndCache() {
    // Several ViewModels start at once. Share one in-flight request instead of
    // sending the same /employee/me call for the dashboard and attendance tabs.
    final Future<Employee>? pending = _inFlightFetch;
    if (pending != null) return pending;

    final Future<Employee> fetch = api.fetchEmployee().then(
      (Employee employee) async {
        await storage.putEmployee(employee);
        return employee;
      },
    );
    _inFlightFetch = fetch;
    // Attach a no-op error handler to the cleanup Future only; callers still
    // receive the original error, but it is never reported as unhandled.
    fetch.then<void>(
      (_) {},
      onError: (Object _) {},
    ).whenComplete(() {
      if (identical(_inFlightFetch, fetch)) _inFlightFetch = null;
    });
    return fetch;
  }

  Future<Employee>? _inFlightFetch;

  /// Never fails: cached employee, or the preconfigured fallback.
  ///
  /// This path is intentionally local-only. Network refresh is owned by the
  /// dashboard's background task, so opening a second tab does not retrigger it.
  Future<Employee> loadForDisplay() async {
    final Employee? cached = await getCached();
    if (cached != null) return cached;

    try {
      return await fetchAndCache();
    } catch (_) {
      return Employee.fallback();
    }
  }
}
