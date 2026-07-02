import '../ash/obfuscator.dart';
import 'gateway_secret.dart';
import 'tracker_secret.dart';
import 'legal_links.dart';

// Masked browser-version fragments for the User-Agent. Kept encoded so obvious
// version strings don't sit in the binary in cleartext.
const List<int> _chromeVer = <int>[
  11, 184, 211, 8, 86, 128, 68, 202, 236, 150, 7, 1, 119, 27,
];
const List<int> _webkitVer = <int>[15, 184, 214, 8, 85, 152];

/// Single source of truth for app-wide identity and tunables.
class RuntimeConfig {
  const RuntimeConfig._();

  static const String bundleId = 'com.magmafall.magmafall';
  static const String storeId = 'com.magmafall.magmafall';
  static const String appName = 'Magma Fall';

  /// PascalCase, space-free token appended to the User-Agent (appname/...).
  static const String uaAppTag = 'MagmaFall';

  /// iOS App Store numeric id — unused on Android.
  static const String storeNumericId = '';

  /// Notification channel id — must match the value in AndroidManifest.xml.
  static const String pulseChannelId = 'magma_signal_channel';
  static const String pulseChannelName = 'Magma Signals';

  /// Skip-again cooldown for the push promo (3 days, in seconds).
  static const int pulseSnoozeSeconds = 3 * 24 * 60 * 60;

  /// Delay before the GCD attribution retry when AppsFlyer says "Organic".
  static const int organicRetrySeconds = 5;

  /// Gateway POST endpoint ('' when not configured yet).
  static String get gatewayUrl => pullGatewayUrl();

  /// AppsFlyer dev key ('' until provided).
  static String get trackerKey => pullTrackerKey();

  /// Firebase sender id ('' until provided).
  static String get senderId => pullSenderId();

  static String get privacyUrl => privacyDoc;
  static String get supportUrl => supportDoc;
  static String get homeUrl => siteHome;

  static String get chromeVersion {
    final v = reveal(_chromeVer);
    return v.isEmpty ? '132.0.6834.163' : v;
  }

  static String get webkitVersion {
    final v = reveal(_webkitVer);
    return v.isEmpty ? '537.36' : v;
  }

  /// Identity suffix appended to every User-Agent (HTTP + WebView) so the
  /// slot/lava backend can recognise the app.
  static String get uaSuffix => 'appid/$bundleId appname/$uaAppTag';
}
