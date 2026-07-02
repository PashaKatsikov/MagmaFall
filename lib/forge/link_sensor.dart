import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Connectivity probe. Treats VPN/bluetooth/other as real interfaces and uses
/// a generous DNS timeout so VPN tunnels don't trip a false "offline".
class LinkSensor {
  final Connectivity _conn = Connectivity();

  static const Set<ConnectivityResult> _live = {
    ConnectivityResult.wifi,
    ConnectivityResult.mobile,
    ConnectivityResult.ethernet,
    ConnectivityResult.vpn,
    ConnectivityResult.bluetooth,
    ConnectivityResult.other,
  };

  static const List<String> _probeHosts = [
    'connectivitycheck.gstatic.com',
    'cloudflare.com',
  ];

  Future<bool> get online async {
    final results = await _conn.checkConnectivity();
    if (!results.any(_live.contains)) return false;

    for (final host in _probeHosts) {
      try {
        final res = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 7));
        if (res.isNotEmpty && res.first.rawAddress.isNotEmpty) return true;
      } on SocketException catch (_) {
        // no route to this host — try the next
      } catch (_) {
        // timeout etc — try the next
      }
    }
    return false;
  }

  Stream<List<ConnectivityResult>> get changes => _conn.onConnectivityChanged;

  static bool allDown(List<ConnectivityResult> r) =>
      r.every((e) => e == ConnectivityResult.none);
}
