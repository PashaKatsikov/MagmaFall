import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bridge/insight.dart';
import 'crust/boot_gate.dart';
import 'forge/attribution_desk.dart';
import 'forge/gate_caller.dart';
import 'forge/link_sensor.dart';
import 'forge/local_store.dart';
import 'forge/signal_center.dart';
import 'forge/ua_client.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + App Check are best-effort: without google-services.json the
  // init throws and the app continues without push (the game still runs).
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  await emberClient.assemble();

  final store = LocalStore();
  await store.warmUp();

  final link = LinkSensor();
  final attribution = AttributionDesk();
  final gate = GateCaller(store);
  final signals = SignalCenter(store);

  runApp(
    ClarityWidget(
      clarityConfig: Insight.config,
      app: MagmaFallApp(
        store: store,
        link: link,
        attribution: attribution,
        gate: gate,
        signals: signals,
      ),
    ),
  );
}

class MagmaFallApp extends StatelessWidget {
  const MagmaFallApp({
    super.key,
    required this.store,
    required this.link,
    required this.attribution,
    required this.gate,
    required this.signals,
  });

  final LocalStore store;
  final LinkSensor link;
  final AttributionDesk attribution;
  final GateCaller gate;
  final SignalCenter signals;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Magma Fall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: MagmaColors.deepRock,
        colorScheme: ColorScheme.fromSeed(
          seedColor: MagmaColors.ember,
          brightness: Brightness.dark,
        ),
      ),
      home: BootGate(
        store: store,
        link: link,
        attribution: attribution,
        gate: gate,
        signals: signals,
      ),
    );
  }
}
