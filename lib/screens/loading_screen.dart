import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_assets.dart';
import '../services/progress_service.dart';
import '../theme.dart';
import 'menu_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _dots;
  double _displayed = 0; // 0..1 shown on the bar
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    // Loading screen is allowed to be shown in any orientation.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _boot();
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    await ProgressService.instance.init();
    await AppAssets.instance.load(onProgress: (p) {
      if (!mounted) return;
      setState(() {
        // The bar tracks real progress but is capped below 100% until launch.
        _displayed = (p * 0.9).clamp(0.0, 0.9);
      });
    });

    // Keep the splash visible for at least a moment so it never flashes by.
    final elapsed = DateTime.now().difference(started);
    const minSplash = Duration(milliseconds: 1400);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }

    if (!mounted) return;
    // Fill the bar fully only in the moment right before launching.
    setState(() {
      _finishing = true;
      _displayed = 1.0;
    });
    await Future.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;

    // The game itself is strictly vertical.
    await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp],
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, a, _) => const MenuScreen(),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MagmaColors.deepRock,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          final bg = isPortrait
              ? 'assets/bg.jpg'
              : 'assets/bg_horizontal.jpg';
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(bg, fit: BoxFit.cover),
              Container(color: MagmaColors.deepRock.withValues(alpha: 0.35)),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 28, vertical: isPortrait ? 24 : 12),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Image.asset('assets/logo.webp'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildProgressBar(),
                      const SizedBox(height: 12),
                      _buildLoadingLabel(),
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

  Widget _buildProgressBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.clamp(0.0, 560.0);
        return Center(
          child: SizedBox(
            width: maxW,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 26,
                decoration: BoxDecoration(
                  color: MagmaColors.deepRock.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MagmaColors.rock, width: 3),
                ),
                child: Stack(
                  children: [
                    // Left-to-right fill.
                    AnimatedFractionallySizedBox(
                      duration: Duration(
                          milliseconds: _finishing ? 500 : 250),
                      curve: Curves.easeOut,
                      alignment: Alignment.centerLeft,
                      widthFactor: _displayed.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              MagmaColors.gold,
                              MagmaColors.ember,
                              MagmaColors.lava,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: MagmaColors.ember,
                              blurRadius: 12,
                            ),
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

  Widget _buildLoadingLabel() {
    return AnimatedBuilder(
      animation: _dots,
      builder: (context, _) {
        final count = (_dots.value * 4).floor() % 4;
        final dots = '.' * count;
        return Text(
          'Loading$dots',
          style: arcadeText(size: 20, color: MagmaColors.cream),
        );
      },
    );
  }
}
