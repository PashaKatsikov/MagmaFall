import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../vent/runtime_config.dart';

/// HTTP client that stamps every request with a real-device browser
/// User-Agent plus the app identity suffix (appid/appname). The same string
/// is handed to the portal WebView so all traffic looks consistent.
class UaClient extends http.BaseClient {
  final http.Client _delegate = http.Client();
  String _agent = 'Mozilla/5.0';

  String get agent => _agent;

  Future<void> assemble() async {
    final chrome = RuntimeConfig.chromeVersion;
    final webkit = RuntimeConfig.webkitVersion;
    final suffix = RuntimeConfig.uaSuffix;

    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final tag = a.display.isNotEmpty ? a.display : a.id;
        _agent = 'Mozilla/5.0 (Linux; Android ${a.version.release}; '
            '${a.model} Build/$tag) AppleWebKit/$webkit (KHTML, like Gecko) '
            'Chrome/$chrome Mobile Safari/$webkit $suffix';
      } else {
        final i = await info.iosInfo;
        final os = i.systemVersion.replaceAll('.', '_');
        _agent = 'Mozilla/5.0 (iPhone; CPU iPhone OS $os like Mac OS X) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Version/${i.systemVersion} Mobile/15E148 Safari/$webkit $suffix';
      }
    } catch (_) {
      _agent = 'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/UP1A) '
          'AppleWebKit/$webkit (KHTML, like Gecko) '
          'Chrome/$chrome Mobile Safari/$webkit $suffix';
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => _agent);
    return _delegate.send(request);
  }

  @override
  void close() => _delegate.close();
}

/// Shared client used by every network-touching service.
final UaClient emberClient = UaClient();
