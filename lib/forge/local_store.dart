import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ash/flow_stage.dart';

/// Wraps SharedPreferences (flags/timestamps) and secure storage (URLs).
class LocalStore {
  static const _kStage = 'mf_stage';
  static const _kPortalUrl = 'mf_portal_u';
  static const _kPortalTtl = 'mf_portal_ttl';
  static const _kSnoozeTs = 'mf_pulse_snooze';
  static const _kPulseAllowed = 'mf_pulse_ok';
  static const _kPulseHardDenied = 'mf_pulse_hard_no';
  static const _kColdPushUrl = 'mf_cold_push_u';

  late final SharedPreferences _prefs;
  final FlutterSecureStorage _safe = const FlutterSecureStorage();

  Future<void> warmUp() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Flow stage ────────────────────────────────────────────
  FlowStage get stage => FlowStage.parse(_prefs.getString(_kStage));
  Future<void> writeStage(FlowStage s) => _prefs.setString(_kStage, s.token);

  // ── Portal URL (secure) + TTL ─────────────────────────────
  Future<String?> readPortalUrl() => _safe.read(key: _kPortalUrl);
  Future<void> writePortalUrl(String url) =>
      _safe.write(key: _kPortalUrl, value: url);

  int? get portalTtl => _prefs.getInt(_kPortalTtl);
  Future<void> writePortalTtl(int ts) => _prefs.setInt(_kPortalTtl, ts);

  bool get portalExpired {
    final ttl = portalTtl;
    if (ttl == null) return true;
    return _nowSec() >= ttl;
  }

  // ── Push promo bookkeeping ────────────────────────────────
  bool get pulseAllowed => _prefs.getBool(_kPulseAllowed) ?? false;
  Future<void> writePulseAllowed(bool v) => _prefs.setBool(_kPulseAllowed, v);

  bool get pulseHardDenied => _prefs.getBool(_kPulseHardDenied) ?? false;
  Future<void> markPulseHardDenied() =>
      _prefs.setBool(_kPulseHardDenied, true);

  int? get pulseSnoozeUntil => _prefs.getInt(_kSnoozeTs);
  Future<void> writePulseSnooze(int ts) => _prefs.setInt(_kSnoozeTs, ts);

  /// Whether the push-promo screen should be shown before the portal.
  bool get shouldPromptPulse {
    if (pulseAllowed) return false; // already granted
    if (pulseHardDenied) return false; // OS won't show the dialog again
    final until = pulseSnoozeUntil;
    if (until == null) return true; // first time
    return _nowSec() >= until;
  }

  // ── One-shot cold-start push URL (secure) ─────────────────
  Future<void> stashColdPushUrl(String? url) async {
    if (url == null) {
      await _safe.delete(key: _kColdPushUrl);
    } else {
      await _safe.write(key: _kColdPushUrl, value: url);
    }
  }

  Future<String?> takeColdPushUrl() async {
    final url = await _safe.read(key: _kColdPushUrl);
    if (url != null) await _safe.delete(key: _kColdPushUrl);
    return url;
  }

  static int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
