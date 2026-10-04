import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether the device has a network connection, from `connectivity_plus`.
///
/// A connection doesn't guarantee the server is reachable (e.g. a captive
/// Wi-Fi portal); uploads still fail and retry in that case.
class NetworkStatus {
  NetworkStatus([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<bool> isOnline() async =>
      _hasConnection(await _connectivity.checkConnectivity());

  /// Emits whenever the device goes online or offline.
  Stream<bool> get onlineChanges =>
      _connectivity.onConnectivityChanged.map(_hasConnection).distinct();

  static bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
