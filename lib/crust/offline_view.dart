import 'package:flutter/material.dart';

import '../bridge/insight.dart';

/// Shown when the portal path has no connection. Uses the project's custom
/// full-screen artwork (orientation aware) with an ember Retry button.
class OfflineView extends StatefulWidget {
  const OfflineView({super.key, required this.onRetry});

  /// Builds the screen to return to once the user retries.
  final WidgetBuilder onRetry;

  @override
  State<OfflineView> createState() => _OfflineViewState();
}

class _OfflineViewState extends State<OfflineView>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    Insight.screen('offline');
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_busy) return;
    Insight.event('offline_retry');
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: widget.onRetry));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bg = landscape
        ? 'assets/Horizontal_Nowifi_Screen.webp'
        : 'assets/Vertical_Nowifi_Screen.jpg';

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
              left: landscape ? size.width * 0.28 : 30,
              right: landscape ? size.width * 0.28 : 30,
              bottom: size.height * (landscape ? 0.08 : 0.09),
              child: _EmberButton(
                label: _busy ? 'Connecting...' : 'Retry',
                busy: _busy,
                pulse: _breath,
                onTap: _retry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chunky lava-gradient action button with a soft breathing glow. Deliberately
/// a rounded rectangle (not a pill) with an outer ring — distinct silhouette.
class _EmberButton extends StatefulWidget {
  const _EmberButton({
    required this.label,
    required this.onTap,
    required this.pulse,
    this.busy = false,
  });

  final String label;
  final VoidCallback onTap;
  final Animation<double> pulse;
  final bool busy;

  @override
  State<_EmberButton> createState() => _EmberButtonState();
}

class _EmberButtonState extends State<_EmberButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.busy ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: widget.busy
          ? null
          : (_) {
              setState(() => _down = false);
              widget.onTap();
            },
      child: AnimatedBuilder(
        animation: widget.pulse,
        builder: (_, _) {
          final glow = 0.3 + widget.pulse.value * 0.5;
          return AnimatedScale(
            scale: _down ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 90),
            child: Container(
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFF8A2B), Color(0xFFFF3B1F), Color(0xFFC81E00)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFFFE1A6), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5A1F).withValues(alpha: glow),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.busy) ...[
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFFFFF3D6)),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Color(0xFFFFF6E6),
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      shadows: [
                        Shadow(color: Color(0x99000000), offset: Offset(0, 2), blurRadius: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
