import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../vent/runtime_config.dart';
import 'local_store.dart';
import 'ua_client.dart';

const String _flameIcon = '@drawable/ic_signal_flame';

@pragma('vm:entry-point')
Future<void> _bgSignal(RemoteMessage message) async {
  // OS renders the tray notification; taps are picked up on resume/cold-start.
}

/// Firebase Messaging + local-notification presenter. Fails silently when
/// Firebase isn't configured yet — the game keeps working without push.
class SignalCenter {
  SignalCenter(this._store);

  final LocalStore _store;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _fcm;
  String? _token;
  bool _ready = false;

  /// Warm-tap URL delivery (background/foreground). NOT persisted.
  void Function(String url)? onWarmUrl;

  /// FCM token rotation → re-POST to the gateway.
  void Function(String token)? onTokenRotated;

  String? get token => _token;

  Future<void> ignite() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      _fcm = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(_bgSignal);
      await _setupLocal();

      _token = await _fcm!.getToken();
      _fcm!.onTokenRefresh.listen((t) {
        _token = t;
        onTokenRotated?.call(t);
      });

      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_onWarmOpen);

      final cold = await _fcm!.getInitialMessage();
      if (cold != null) _onColdOpen(cold);

      _ready = true;
    } catch (_) {
      // No Firebase config — push disabled.
    }
  }

  Future<void> _setupLocal() async {
    const android = AndroidInitializationSettings(_flameIcon);
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          final url = data['url'] as String?;
          if (url != null && url.isNotEmpty) onWarmUrl?.call(url);
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          RuntimeConfig.pulseChannelId,
          RuntimeConfig.pulseChannelName,
          description: 'Updates and offers',
          importance: Importance.high,
        ),
      );
    }
  }

  /// Asks for notification permission. Records a hard-deny so the promo isn't
  /// shown again pointlessly (OS won't reopen the dialog after a deny).
  /// After the user grants permission, refreshes the FCM token — on Android 13+
  /// getToken() can return null before the POST_NOTIFICATIONS permission is set.
  Future<bool> askPermission() async {
    if (_fcm == null) {
      await _store.writePulseAllowed(false);
      return false;
    }
    final settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final status = settings.authorizationStatus;
    final granted = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;

    await _store.writePulseAllowed(granted);

    if (status == AuthorizationStatus.denied) {
      await _store.markPulseHardDenied();
    }

    // Re-fetch FCM token now that the permission is confirmed.
    // On Android 13+ the OS may have blocked getToken() during ignite().
    if (granted && (_token == null || _token!.isEmpty)) {
      try {
        _token = await _fcm!.getToken();
        if (_token != null) onTokenRotated?.call(_token!);
      } catch (_) {}
    }

    return granted;
  }

  void _onForeground(RemoteMessage message) async {
    final note = message.notification;
    if (note == null || !Platform.isAndroid) return;

    final imageUrl = note.android?.imageUrl;
    AndroidNotificationDetails? details;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      final bytes = await _grabImage(imageUrl);
      if (bytes != null) {
        details = AndroidNotificationDetails(
          RuntimeConfig.pulseChannelId,
          RuntimeConfig.pulseChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: _flameIcon,
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bytes),
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      }
    }

    details ??= AndroidNotificationDetails(
      RuntimeConfig.pulseChannelId,
      RuntimeConfig.pulseChannelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: _flameIcon,
    );

    await _local.show(
      note.hashCode,
      note.title,
      note.body,
      NotificationDetails(android: details),
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );
  }

  void _onColdOpen(RemoteMessage message) {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) _store.stashColdPushUrl(url);
  }

  void _onWarmOpen(RemoteMessage message) {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) onWarmUrl?.call(url);
  }

  Future<Uint8List?> _grabImage(String url) async {
    try {
      final resp =
          await emberClient.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }
}
