import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../app_assets.dart';
import '../bridge/insight.dart';
import '../services/progress_service.dart';
import '../theme.dart';
import 'game_painter.dart';
import 'game_world.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  GameWorld? _world;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  bool _paused = false;
  bool _scoreSubmitted = false;
  int _finalScore = 0;
  int _bestScore = 0;
  bool _newBest = false;

  @override
  void initState() {
    super.initState();
    Insight.screen('game');
    _bestScore = ProgressService.instance.bestScore;
    _ticker = createTicker(_onTick);
  }

  // ---------------------------------------------------------------------------
  // World lifecycle
  // ---------------------------------------------------------------------------

  void _startWorld(Size size) {
    _world?.releaseTouch();
    _world = GameWorld(size: size);
    _last = Duration.zero;
    _paused = false;
    _scoreSubmitted = false;
    _newBest = false;
    _finalScore = 0;
    _ticker.stop();
    _ticker.start();
  }

  Future<void> _onGameOver() async {
    if (_scoreSubmitted) return;
    _scoreSubmitted = true;
    // Capture score synchronously so the overlay shows it on first frame.
    _finalScore = _world?.score ?? 0;
    _bestScore = ProgressService.instance.bestScore;
    _newBest = await ProgressService.instance.submitScore(_finalScore);
    if (_newBest) _bestScore = _finalScore;
    Insight.event('game_over');
    Insight.tag('game_score', '$_finalScore');
    if (_newBest) Insight.event('game_new_best');
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Game loop
  // ---------------------------------------------------------------------------

  void _onTick(Duration now) {
    final world = _world;
    if (world == null) return;
    if (_last == Duration.zero) {
      _last = now;
      return;
    }
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;

    if (!_paused && world.status == GameStatus.playing) {
      world.update(dt);
      if (world.status == GameStatus.lost) _onGameOver();
    }
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Raw pointer input – Listener fires before the gesture arena, guaranteed.
  // ---------------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent e) {
    if (_paused || _world?.status != GameStatus.playing) return;
    _world!.touchAt(e.localPosition.dx);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_paused || _world?.status != GameStatus.playing) return;
    _world!.touchAt(e.localPosition.dx);
  }

  void _onPointerUp(PointerUpEvent e) => _world?.releaseTouch();
  void _onPointerCancel(PointerCancelEvent e) => _world?.releaseTouch();

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _retry() {
    final size = context.size;
    if (size != null) setState(() => _startWorld(size));
  }

  void _togglePause() {
    if (_world?.status == GameStatus.lost) return;
    setState(() {
      _paused = !_paused;
      if (_paused) _world?.releaseTouch();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MagmaColors.deepRock,
      body: LayoutBuilder(builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        if (_world == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _world == null) setState(() => _startWorld(size));
          });
          return const SizedBox.expand();
        }

        final world = _world!;
        final showGameOver = world.status == GameStatus.lost;
        final showPause = _paused && !showGameOver;

        return SizedBox.expand(
          child: Stack(
          children: [
            // ── 1. Background image – Flutter widget, always fills screen ─────
            Positioned.fill(
              child: RawImage(
                image: AppAssets.instance.bg,
                fit: BoxFit.cover,
              ),
            ),

            // ── 2. Game canvas (transparent; darkens bg via painter) ──────────
            //    Listener receives raw pointer events unconditionally – it does
            //    NOT go through the gesture arena, so it cannot be cancelled.
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: CustomPaint(painter: GamePainter(world)),
              ),
            ),

            // ── 3. HUD (rendered on top; InkWell handles its own taps) ────────
            _buildHud(world),

            // ── 4. Overlays – NOTE: Positioned.fill is here in the Stack, NOT
            //    inside _Overlay.build(), because Stack only recognises
            //    Positioned widgets that are its DIRECT children. ───────────────
            if (showGameOver)
              Positioned.fill(
                child: _Overlay(
                  child: _GameOverContent(
                    finalScore: _finalScore,
                    bestScore: _bestScore,
                    newBest: _newBest,
                    onRetry: _retry,
                    onMenu: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            if (showPause)
              Positioned.fill(
                child: _Overlay(
                  child: _PauseContent(
                    onResume: _togglePause,
                    onRetry: _retry,
                    onMenu: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
          ],
        ));
      }),
    );
  }

  Widget _buildHud(GameWorld world) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ScoreChip(score: world.score),
            const Spacer(),
            _HudButton(
              icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              onTap: _togglePause,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay widget.
// IMPORTANT: The caller (Stack in _GameScreenState) wraps this in
// Positioned.fill. Do NOT add Positioned.fill here – Stack ignores Positioned
// widgets that are not its direct children.
// ---------------------------------------------------------------------------
class _Overlay extends StatelessWidget {
  const _Overlay({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // GestureDetector with opaque behaviour absorbs all touches so the
    // Listener on the game canvas below does not fire.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (_) {},
      child: DecoratedBox(
        decoration: const BoxDecoration(color: MagmaColors.shadow),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Content widgets
// ---------------------------------------------------------------------------

class _GameOverContent extends StatelessWidget {
  const _GameOverContent({
    required this.finalScore,
    required this.bestScore,
    required this.newBest,
    required this.onRetry,
    required this.onMenu,
  });

  final int finalScore;
  final int bestScore;
  final bool newBest;
  final VoidCallback onRetry;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'CAUGHT BY LAVA!',
          textAlign: TextAlign.center,
          style: arcadeText(size: 30, color: MagmaColors.lava),
        ),
        const SizedBox(height: 20),
        if (newBest) ...[
          Text('NEW BEST!',
              style: arcadeText(size: 22, color: MagmaColors.gold)),
          const SizedBox(height: 8),
        ],
        Text('SCORE', style: arcadeText(size: 15, color: MagmaColors.cream)),
        const SizedBox(height: 4),
        Text(
          '$finalScore',
          style: arcadeText(size: 52, color: MagmaColors.gold),
        ),
        const SizedBox(height: 8),
        Text(
          'BEST  $bestScore',
          style: arcadeText(size: 15, color: MagmaColors.cream),
        ),
        const SizedBox(height: 30),
        MagmaButton(
          label: 'PLAY AGAIN',
          icon: Icons.refresh_rounded,
          width: 240,
          onPressed: onRetry,
        ),
        const SizedBox(height: 14),
        MagmaButton(
          label: 'MENU',
          icon: Icons.home_rounded,
          width: 240,
          color: MagmaColors.rock,
          onPressed: onMenu,
        ),
      ],
    );
  }
}

class _PauseContent extends StatelessWidget {
  const _PauseContent({
    required this.onResume,
    required this.onRetry,
    required this.onMenu,
  });

  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('PAUSED', style: arcadeText(size: 34, color: MagmaColors.gold)),
        const SizedBox(height: 28),
        MagmaButton(
          label: 'RESUME',
          icon: Icons.play_arrow_rounded,
          width: 240,
          onPressed: onResume,
        ),
        const SizedBox(height: 14),
        MagmaButton(
          label: 'RESTART',
          icon: Icons.refresh_rounded,
          width: 240,
          color: MagmaColors.rock,
          onPressed: onRetry,
        ),
        const SizedBox(height: 14),
        MagmaButton(
          label: 'MENU',
          icon: Icons.home_rounded,
          width: 240,
          color: MagmaColors.rock,
          onPressed: onMenu,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// HUD widgets
// ---------------------------------------------------------------------------

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: MagmaColors.shadow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MagmaColors.rock, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: MagmaColors.gold, size: 20),
          const SizedBox(width: 8),
          Text('$score', style: arcadeText(size: 20)),
        ],
      ),
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MagmaColors.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: MagmaColors.rock, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: MagmaColors.cream, size: 24),
        ),
      ),
    );
  }
}
