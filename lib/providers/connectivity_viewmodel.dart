import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/network/connectivity_service.dart';

class ConnectivityViewModel extends ChangeNotifier {
  final ConnectivityService service;

  ConnectivityViewModel(this.service);

  bool _isOnline = true;
  StreamSubscription<bool>? _subscription;

  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  /// Allows offline/online simulation in tests and demos without a platform
  /// channel. Not used by production UI.
  void setOnlineState(bool value) {
    if (_isOnline == value) return;
    _isOnline = value;
    notifyListeners();
  }

  Future<void> init() async {
    _isOnline = await service.isOnline;
    notifyListeners();
    _subscription?.cancel();
    _subscription = service.onConnectivityChanged.listen((bool online) {
      if (online == _isOnline) return;
      _isOnline = online;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
