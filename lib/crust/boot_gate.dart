import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_assets.dart';
import '../ash/flow_stage.dart';
import '../bridge/insight.dart';
import '../forge/attribution_desk.dart';
import '../forge/gate_caller.dart';
import '../forge/link_sensor.dart';
import '../forge/local_store.dart';
import '../forge/signal_center.dart';
import '../screens/menu_screen.dart';
import '../services/progress_service.dart';
import '../theme.dart';
import 'offline_view.dart';
import 'portal_view.dart';
import 'pulse_prompt.dart';

/// Boot orchestrator. Renders the adaptive loading screen and decides between
/// the portal (web) and the volcano game (native). The game path never needs
/// a network, so the white part launches fully offline.
class BootGate extends StatefulWidget {
  const BootGate({
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
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> with TickerProviderStateMixin {
  late final AnimationController _dots;
  double _fill = 0;
  bool _sealing = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    Insight.screen('loading');
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _drive();
  }

  @override
  void dispose() {
    widget.signals.onTokenRotated = null;
    _dots.dispose();
    super.dispose();
  }

  String _locale() => Platform.localeName.replaceAll('-', '_');

  Future<void> _drive() async {
    widget.signals.onTokenRotated = _reportToken;
    await widget.signals.ignite();
    _setFill(0.15);

    switch (widget.store.stage) {
      case FlowStage.web:
        await _returningWeb();
        break;
      case FlowStage.native:
        await _bootGame(minHold: const Duration(milliseconds: 600));
        break;
      case FlowStage.unresolved:
        await _firstLaunch();
        break;
    }
  }

  void _reportToken(String token) async {
    final body = await widget.attribution.composeBody(
      locale: _locale(),
      pushToken: token,
    );
    widget.gate.ask(body);
  }

  Future<void> _firstLaunch() async {
    if (!await widget.link.online) {
      Insight.event('route_offline');
      _goOffline();
      return;
    }

    _setFill(0.5);
    await widget.attribution.ignite();
    await Future.wait([
      widget.attribution.awaitAttribution(),
      widget.attribution.awaitDeepLink(),
    ]);

    final body = await widget.attribution.composeBody(
      locale: _locale(),
      pushToken: widget.signals.token,
    );

    Insight.identify(
      body['af_id']?.toString(),
      tags: {
        'af_status': body['af_status']?.toString() ?? '',
        'media_source': body['media_source']?.toString() ?? '',
        'campaign': body['campaign']?.toString() ?? '',
        'os': body['os']?.toString() ?? '',
        'locale': body['locale']?.toString() ?? '',
      },
    );

    final reply = await widget.gate.ask(body);

    if (reply.ok && reply.hasUrl) {
      Insight.tag('run_mode', 'web');
      Insight.event('route_web');
      await widget.store.writeStage(FlowStage.web);
      await _seal();
      _openPortal(reply.url!);
    } else {
      Insight.tag('run_mode', 'native');
      Insight.event('route_native');
      await widget.store.writeStage(FlowStage.native);
      await _bootGame();
    }
  }

  Future<void> _returningWeb() async {
    if (!await widget.link.online) {
      Insight.event('route_offline');
      await _seal();
      _goOffline();
      return;
    }

    final coldPush = await widget.store.takeColdPushUrl();
    if (coldPush != null) {
      Insight.tag('run_mode', 'web');
      Insight.event('route_push_link');
      await _seal();
      _openPortal(coldPush);
      return;
    }

    final cached = await widget.store.readPortalUrl();

    await widget.attribution.ignite();
    await Future.wait([
      widget.attribution
          .awaitAttribution(limit: const Duration(seconds: 10)),
      widget.attribution.awaitDeepLink(),
    ]);

    final body = await widget.attribution.composeBody(
      locale: _locale(),
      pushToken: widget.signals.token,
    );

    Insight.identify(
      body['af_id']?.toString(),
      tags: {
        'af_status': body['af_status']?.toString() ?? '',
        'media_source': body['media_source']?.toString() ?? '',
        'campaign': body['campaign']?.toString() ?? '',
        'os': body['os']?.toString() ?? '',
        'locale': body['locale']?.toString() ?? '',
      },
    );

    final reply = await widget.gate.ask(body);
    await _seal();

    if (reply.ok && reply.hasUrl) {
      Insight.tag('run_mode', 'web');
      Insight.event('route_web');
      _openPortal(reply.url!);
    } else if (cached != null) {
      Insight.tag('run_mode', 'web');
      Insight.event('route_cached_link');
      _openPortal(cached);
    } else {
      Insight.event('route_offline');
      _goOffline();
    }
  }

  /// Loads game resources and enters the white part.
  Future<void> _bootGame({Duration? minHold}) async {
    _setFill(0.55);
    final started = DateTime.now();
    await ProgressService.instance.init();
    await AppAssets.instance.load(onProgress: (p) {
      _setFill((0.55 + p * 0.4).clamp(0.0, 0.95));
    });

    final hold = minHold ?? const Duration(milliseconds: 400);
    final spent = DateTime.now().difference(started);
    if (spent < hold) await Future.delayed(hold - spent);

    await _seal();
    if (!mounted) return;
    await SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp]);
    if (!mounted) return;
    _swap(const MenuScreen());
  }

  Future<void> _seal() async {
    if (!mounted) return;
    setState(() {
      _sealing = true;
      _fill = 1.0;
    });
    await Future.delayed(const Duration(milliseconds: 520));
  }

  void _openPortal(String url) {
    if (_left || !mounted) return;
    if (widget.store.shouldPromptPulse) {
      _swap(PulsePrompt(
        store: widget.store,
        signals: widget.signals,
        link: widget.link,
        attribution: widget.attribution,
        gate: widget.gate,
        portalUrl: url,
      ));
    } else {
      Insight.tag(
        'notif_permission',
        widget.store.pulseAllowed
            ? 'granted'
            : widget.store.pulseHardDenied
                ? 'os_denied'
                : 'snoozed',
      );
      _swap(PortalView(
        url: url,
        store: widget.store,
        signals: widget.signals,
        link: widget.link,
        attribution: widget.attribution,
        gate: widget.gate,
      ));
    }
  }

  void _goOffline() {
    if (_left || !mounted) return;
    _swap(OfflineView(
      onRetry: (_) => BootGate(
        store: widget.store,
        link: widget.link,
        attribution: widget.attribution,
        gate: widget.gate,
        signals: widget.signals,
      ),
    ));
  }

  void _swap(Widget page) {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  void _setFill(double v) {
    if (!mounted || _sealing) return;
    setState(() => _fill = v.clamp(0.0, 0.95));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MagmaColors.deepRock,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final portrait = orientation == Orientation.portrait;
          final bg = portrait ? 'assets/bg.jpg' : 'assets/bg_horizontal.jpg';
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(bg, fit: BoxFit.cover),
              Container(color: MagmaColors.deepRock.withValues(alpha: 0.35)),
              // SafeArea только по вертикали — горизонтальное пространство
              // не ограничиваем, чтобы логотип и бар были точно по центру
              // экрана даже на устройствах с боковым вырезом камеры.
              SafeArea(
                left: false,
                right: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      vertical: portrait ? 24 : 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: portrait
                                  ? MediaQuery.of(context).size.width * 0.85
                                  : MediaQuery.of(context).size.height * 0.75,
                            ),
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Image.asset('assets/logo.webp'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: _bar(),
                      ),
                      const SizedBox(height: 12),
                      _label(),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bar() {
    const radius = 13.0;
    final fill = _fill.clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.clamp(0.0, 560.0);
        return Center(
          child: SizedBox(
            width: w,
            child: Container(
              height: 26,
              decoration: BoxDecoration(
                color: MagmaColors.deepRock.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: MagmaColors.rock, width: 3),
              ),
              // ClipRRect обрезает заливку строго по форме контейнера
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius - 3),
                child: Stack(
                  children: [
                    AnimatedFractionallySizedBox(
                      duration: Duration(milliseconds: _sealing ? 500 : 260),
                      curve: Curves.easeOut,
                      alignment: Alignment.centerLeft,
                      widthFactor: fill,
                      heightFactor: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            MagmaColors.gold,
                            MagmaColors.ember,
                            MagmaColors.lava,
                          ]),
                          // Правый торец всегда скруглён независимо от fill
                          borderRadius: BorderRadius.circular(radius - 3),
                          boxShadow: const [
                            BoxShadow(color: MagmaColors.ember, blurRadius: 12),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _label() {
    return AnimatedBuilder(
      animation: _dots,
      builder: (context, _) {
        final n = (_dots.value * 4).floor() % 4;
        return Text('Loading${'.' * n}',
            style: arcadeText(size: 20, color: MagmaColors.cream));
      },
    );
  }
}
