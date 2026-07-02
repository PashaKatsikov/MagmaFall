import 'dart:ui' as ui;
import 'package:flutter/services.dart';

/// Central holder for all decoded [ui.Image] sprites used by the game.
///
/// Images are decoded once (during the loading screen) so the game loop can
/// draw them synchronously through a [CustomPainter] without any async gaps.
class AppAssets {
  AppAssets._();

  static final AppAssets instance = AppAssets._();

  bool _loaded = false;
  bool get loaded => _loaded;

  late final ui.Image bg;
  late final ui.Image bgHorizontal;
  late final ui.Image logo;

  late final ui.Image character;
  late final ui.Image characterFalling;
  late final ui.Image characterSquashed;

  late final ui.Image platform;
  late final ui.Image platformCracked;
  late final ui.Image platformFloating;
  late final ui.Image platformCloud;
  late final ui.Image platformIcy;
  late final ui.Image platformBouncy;

  late final ui.Image bat;
  late final ui.Image meteor;

  /// Decodes every sprite. [onProgress] is reported in the range 0..1 so the
  /// loading screen can render a real progress bar tied to actual work.
  Future<void> load({void Function(double progress)? onProgress}) async {
    if (_loaded) {
      onProgress?.call(1);
      return;
    }

    final entries = <String, void Function(ui.Image)>{
      'assets/bg.jpg': (i) => bg = i,
      'assets/bg_horizontal.jpg': (i) => bgHorizontal = i,
      'assets/logo.webp': (i) => logo = i,
      'assets/character.webp': (i) => character = i,
      'assets/character_falling_pose.webp': (i) => characterFalling = i,
      'assets/character_squashed_landing_pose.webp': (i) => characterSquashed = i,
      'assets/platform.webp': (i) => platform = i,
      'assets/platform_cracked.webp': (i) => platformCracked = i,
      'assets/platform_floating.webp': (i) => platformFloating = i,
      'assets/platform_cloud_ash.webp': (i) => platformCloud = i,
      'assets/platform_icy.webp': (i) => platformIcy = i,
      'assets/platform_bouncy_mushroom.webp': (i) => platformBouncy = i,
      'assets/angry_fire_bat.webp': (i) => bat = i,
      'assets/meteor.webp': (i) => meteor = i,
    };

    var done = 0;
    final total = entries.length;
    for (final entry in entries.entries) {
      final image = await _decode(entry.key);
      entry.value(image);
      done++;
      onProgress?.call(done / total);
    }

    _loaded = true;
  }

  Future<ui.Image> _decode(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
