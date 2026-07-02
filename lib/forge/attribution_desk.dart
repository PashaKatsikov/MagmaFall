import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../vent/runtime_config.dart';
import '../vent/tracker_secret.dart';
import 'ua_client.dart';

/// Owns the AppsFlyer SDK: collects install attribution + deep-link data and
/// assembles the POST body sent to the gateway.
///
/// Degrades gracefully: if no tracker key is configured yet, the SDK is never
/// started and the attribution future resolves immediately with an empty map
/// (so the boot flow doesn't stall on the 30s wait).
class AttributionDesk {
  AppsflyerSdk? _sdk;

  Map<String, dynamic> _attr = {};
  Map<String, dynamic> _deep = {};
  Map<String, dynamic> _appOpen = {};

  final Completer<Map<String, dynamic>> _attrDone = Completer();
  final Completer<void> _deepDone = Completer();
  bool _started = false;

  bool get _enabled => RuntimeConfig.trackerKey.isNotEmpty;

  Future<void> ignite() async {
    if (_started) return;
    _started = true;

    if (!_enabled) {
      _settleAttr({});
      _settleDeep();
      return;
    }

    try {
      final opts = AppsFlyerOptions(
        afDevKey: RuntimeConfig.trackerKey,
        appId: RuntimeConfig.storeNumericId,
        showDebug: kDebugMode,
        timeToWaitForATTUserAuthorization: 10,
      );
      final sdk = AppsflyerSdk(opts);
      _sdk = sdk;

      sdk.onInstallConversionData((res) async {
        final payload = _extract(res);
        if ((payload['af_status']?.toString() ?? '') == 'Organic') {
          await Future.delayed(
              Duration(seconds: RuntimeConfig.organicRetrySeconds));
          final fresh = await _regrabConversion();
          _settleAttr(fresh ?? payload);
        } else {
          _settleAttr(payload);
        }
      });

      sdk.onAppOpenAttribution((res) {
        _appOpen = _extract(res);
      });

      sdk.onDeepLinking((DeepLinkResult dp) {
        final ce = dp.deepLink?.clickEvent;
        if (ce != null) _deep = Map<String, dynamic>.from(ce);
        _settleDeep();
      });

      await sdk.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (_) {
      _settleAttr({});
      _settleDeep();
    }
  }

  Future<Map<String, dynamic>> awaitAttribution({
    Duration limit = const Duration(seconds: 30),
  }) {
    return _attrDone.future
        .timeout(limit, onTimeout: () => <String, dynamic>{});
  }

  Future<void> awaitDeepLink({
    Duration limit = const Duration(seconds: 5),
  }) {
    return _deepDone.future.timeout(limit, onTimeout: () {});
  }

  Future<String?> installId() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Builds the merged gateway request payload. Attribution fields are passed
  /// through untouched; device fields are always appended.
  Future<Map<String, dynamic>> composeBody({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};
    body.addAll(_attr);
    _deep.forEach((k, v) => body.putIfAbsent(k, () => v));
    _appOpen.forEach((k, v) => body.putIfAbsent(k, () => v));

    body['af_id'] = await installId() ?? '';
    body['bundle_id'] = RuntimeConfig.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = RuntimeConfig.storeId;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    if (RuntimeConfig.senderId.isNotEmpty) {
      body['firebase_project_id'] = RuntimeConfig.senderId;
    }

    if (kDebugMode) {
      debugPrint('[AttributionDesk] body => ${jsonEncode(body)}');
    }
    return body;
  }

  // ── internals ─────────────────────────────────────────────

  Future<Map<String, dynamic>?> _regrabConversion() async {
    try {
      final uid = await installId();
      if (uid == null) return null;
      final appId =
          Platform.isIOS ? RuntimeConfig.storeNumericId : RuntimeConfig.bundleId;
      final url = buildSyncEndpoint(appId, uid);
      if (url.isEmpty) return null;

      final resp = await emberClient.get(
        Uri.parse(url),
        headers: {'authorization': 'Bearer ${RuntimeConfig.trackerKey}'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// AppsFlyer SDK delivers the conversion payload wrapped differently on
  /// different platforms/versions:
  ///   • Android (appsflyer_sdk 6.x): `{status, type, data: { af_status, ... }}`
  ///   • Some builds:                 `{payload: { af_status, ... }, ...}`
  ///   • Older/direct:                `{ af_status, ... }` at the top level.
  /// Missing this unwrap means the raw envelope is forwarded to the gateway,
  /// which then can't find `af_status` / `campaign` / `af_id` and rejects the
  /// install with "Application install not found".
  Map<String, dynamic> _extract(dynamic res) {
    try {
      if (res is Map) {
        final inner = res['payload'] ?? res['data'] ?? res;
        if (inner is Map) {
          return Map<String, dynamic>.from(inner);
        }
      }
    } catch (_) {}
    return {};
  }

  void _settleAttr(Map<String, dynamic> data) {
    _attr = data;
    if (!_attrDone.isCompleted) _attrDone.complete(data);
  }

  void _settleDeep() {
    if (!_deepDone.isCompleted) _deepDone.complete();
  }
}
