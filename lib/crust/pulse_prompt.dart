import 'dart:io';

import 'package:flutter/material.dart';

import '../forge/attribution_desk.dart';
import '../forge/gate_caller.dart';
import '../forge/link_sensor.dart';
import '../forge/local_store.dart';
import '../forge/signal_center.dart';
import '../vent/runtime_config.dart';
import 'portal_view.dart';

/// Push opt-in promo shown once before the portal. Full-screen custom artwork
/// with an Accept (ember) and a Skip (ghost) control.
class PulsePrompt extends StatefulWidget {
  const PulsePrompt({
    super.key,
    required this.store,
    required this.signals,
    required this.link,
    required this.attribution,
    required this.gate,
    required this.portalUrl,
  });

  final LocalStore store;
  final SignalCenter signals;
  final LinkSensor link;
  final AttributionDesk attribution;
  final GateCaller gate;
  final String portalUrl;

  @override
  State<PulsePrompt> createState() => _PulsePromptState();
}

class _PulsePromptState extends State<PulsePrompt> {
  bool _leaving = false;

  Future<void> _accept() async {
    if (_leaving) return;

    // Wire up the token reporter before asking for permission.
    // BootGate is already gone at this point (pushReplacement), so we install
    // the handler here so the freshly fetched token reaches the gateway.
    widget.signals.onTokenRotated = _reportToken;

    final granted = await widget.signals.askPermission();
    if (!granted) {
      final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          RuntimeConfig.pulseSnoozeSeconds;
      await widget.store.writePulseSnooze(until);
    }
    _proceed();
  }

  void _reportToken(String token) {
    widget.attribution
        .composeBody(
          locale: Platform.localeName.replaceAll('-', '_'),
          pushToken: token,
        )
        .then(widget.gate.ask)
        .ignore();
  }

  Future<void> _skip() async {
    if (_leaving) return;
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        RuntimeConfig.pulseSnoozeSeconds;
    await widget.store.writePulseSnooze(until);
    _proceed();
  }

  void _proceed() {
    if (_leaving || !mounted) return;
    _leaving = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PortalView(
          url: widget.portalUrl,
          store: widget.store,
          signals: widget.signals,
          link: widget.link,
          attribution: widget.attribution,
          gate: widget.gate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bg = landscape
        ? 'assets/Horizontal_Notifications_Screen.jpg'
        : 'assets/Vertical_Notifications_Screen.jpg';

    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AcceptButton(onTap: _accept, compact: landscape),
        SizedBox(height: landscape ? 6 : 14),
        _SkipButton(onTap: _skip),
      ],
    );

    return Scaffold(
      backgroundColor: const Color(0xFF160A06),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(bg, fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Color(0xFF160A06))),
            Positioned(
              left: landscape ? size.width * 0.30 : size.width * 0.10,
              right: landscape ? size.width * 0.30 : size.width * 0.10,
              bottom: size.height * (landscape ? 0.06 : 0.08),
              child: controls,
            ),
          ],
        ),
      ),
    );
  }
}

class _AcceptButton extends StatefulWidget {
  const _AcceptButton({required this.onTap, this.compact = false});
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_AcceptButton> createState() => _AcceptButtonState();
}

class _AcceptButtonState extends State<_AcceptButton>
    with SingleTickerProviderStateMixin {
  bool _down = false;
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: _glow,
        builder: (_, _) => AnimatedScale(
          scale: _down ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: widget.compact ? 13 : 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFB13C), Color(0xFFFF5A1F), Color(0xFFD11E00)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFE7B8), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF5A1F)
                      .withValues(alpha: 0.3 + _glow.value * 0.45),
                  blurRadius: 20 + _glow.value * 14,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                'Accept',
                style: TextStyle(
                  color: const Color(0xFF2A0A00),
                  fontSize: widget.compact ? 17 : 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkipButton extends StatefulWidget {
  const _SkipButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends State<_SkipButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedOpacity(
        opacity: _down ? 0.55 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x66FFE7B8), width: 1.4),
          ),
          child: const Center(
            child: Text(
              'Skip',
              style: TextStyle(
                color: Color(0xFFFFF3D6),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
