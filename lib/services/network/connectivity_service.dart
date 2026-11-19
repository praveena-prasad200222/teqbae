import 'package:connectivity_plus/connectivity_plus.dart';

/// Thin wrapper so ViewModels never depend on the platform plugin directly.
class ConnectivityService {
  final Connectivity _connectivity;

  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  Stream<bool> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged.map(_isOnline);

  Future<bool> get isOnline async => _isOnline(await _connectivity.checkConnectivity());

  bool _isOnline(List<ConnectivityResult> results) =>
      results.isNotEmpty && results.any((ConnectivityResult r) => r != ConnectivityResult.none);
}
