import 'dart:convert';

import '../ash/gate_reply.dart';
import '../vent/runtime_config.dart';
import 'local_store.dart';
import 'ua_client.dart';

/// Talks to the decisioning gateway. Persists a winning URL + expiry so a
/// returning session can fall back to it when the network is flaky.
class GateCaller {
  GateCaller(this._store);

  final LocalStore _store;

  Future<GateReply> ask(Map<String, dynamic> body) async {
    final endpoint = RuntimeConfig.gatewayUrl;
    if (endpoint.isEmpty) return GateReply.failed('no-endpoint');

    try {
      final resp = await emberClient
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return GateReply.failed('http-${resp.statusCode}');
      }

      final reply =
          GateReply.fromMap(jsonDecode(resp.body) as Map<String, dynamic>);

      if (reply.ok && reply.hasUrl) {
        await _store.writePortalUrl(reply.url!);
        if (reply.expires != null) {
          await _store.writePortalTtl(reply.expires!);
        }
      }
      return reply;
    } catch (e) {
      return GateReply.failed(e.toString());
    }
  }

  Future<String?> cachedUrl() => _store.readPortalUrl();
}
