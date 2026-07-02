import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_assets.dart';
import '../theme.dart';
import 'entities.dart';
import 'game_world.dart';

/// Renders the full game scene each frame from the [GameWorld] state.
class GamePainter extends CustomPainter {
  GamePainter(this.world) : assets = AppAssets.instance;

  final GameWorld world;
  final AppAssets assets;

  double _sy(double worldY) => worldY - world.cameraY;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    for (final p in world.platforms) {
      _drawPlatform(canvas, p);
    }
    for (final b in world.bats) {
      _drawBat(canvas, b);
    }
    for (final m in world.meteors) {
      _drawMeteor(canvas, m);
    }
    _drawPlayer(canvas);
    _drawLava(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    // The background image is rendered as a Flutter widget (RawImage) behind
    // this CustomPaint – see game_screen.dart.  We only add a slight darkening
    // here so that sprites are readable against bright areas of the image.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = MagmaColors.deepRock.withValues(alpha: 0.30),
    );
  }

  void _drawSprite(
    Canvas canvas,
    ui.Image img,
    double centerX,
    double centerY,
    double drawWidth, {
    bool flipX = false,
    double rotation = 0,
    double heightScale = 1,
  }) {
    final aspect = img.height / img.width;
    final drawHeight = drawWidth * aspect * heightScale;
    canvas.save();
    canvas.translate(centerX, centerY);
    if (rotation != 0) canvas.rotate(rotation);
    if (flipX) canvas.scale(-1, 1);
    final dst = Rect.fromCenter(
      center: Offset.zero,
      width: drawWidth,
      height: drawHeight,
    );
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  void _drawPlatform(Canvas canvas, GamePlatform p) {
    final screenY = _sy(p.y);
    final opacity = p.broken ? (1 - (p.breakTimer / 0.5)).clamp(0.0, 1.0) : 1.0;
    if (opacity <= 0) return;

    ui.Image img;
    double widthScale;
    double anchor; // fraction of draw height sitting above the surface line
    switch (p.type) {
      case PlatformType.normal:
        img = assets.platform;
        widthScale = 1.45;
        anchor = 0.30;
        break;
      case PlatformType.moving:
        img = assets.platformFloating;
        widthScale = 1.45;
        anchor = 0.30;
        break;
      case PlatformType.cracked:
        img = assets.platformCracked;
        widthScale = 1.5;
        anchor = 0.32;
        break;
      case PlatformType.cloud:
        img = assets.platformCloud;
        widthScale = 1.55;
        anchor = 0.45;
        break;
      case PlatformType.icy:
        img = assets.platformIcy;
        widthScale = 1.5;
        anchor = 0.34;
        break;
      case PlatformType.bouncy:
        img = assets.platformBouncy;
        widthScale = 1.15;
        // Collision (p.y) sits just above the visual centre of the sprite.
        anchor = 0.48;
        break;
    }

    final drawW = p.width * widthScale;
    final aspect = img.height / img.width;
    final drawH = drawW * aspect;
    final centerX = p.centerX;
    final centerY = screenY - anchor * drawH + drawH / 2;

    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (opacity < 1) paint.color = Colors.white.withValues(alpha: opacity);

    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: Offset(centerX, centerY), width: drawW, height: drawH),
      paint,
    );
  }

  void _drawPlayer(Canvas canvas) {
    final pl = world.player;
    final cx = pl.x;
    final cy = _sy(pl.y);

    ui.Image img;
    double width = 74;
    double hScale = 1;
    if (pl.squashed) {
      img = assets.characterSquashed;
      width = 86;
    } else if (pl.falling) {
      img = assets.characterFalling;
    } else {
      img = assets.character;
    }

    // Little squash & stretch on the vertical axis for juicy jumps.
    if (pl.squashed) {
      hScale = 0.9;
    } else if (!pl.falling) {
      hScale = 1.05;
    }

    _drawSprite(canvas, img, cx, cy, width,
        flipX: !pl.facingRight, heightScale: hScale);
  }

  void _drawBat(Canvas canvas, Bat b) {
    final flap = math.sin(b.wing) * 0.12;
    _drawSprite(canvas, assets.bat, b.x, _sy(b.y), 72,
        flipX: b.dir > 0, rotation: flap);
  }

  void _drawMeteor(Canvas canvas, Meteor m) {
    _drawSprite(canvas, assets.meteor, m.x, _sy(m.y), 78, rotation: m.spin);
  }

  void _drawLava(Canvas canvas, Size size) {
    final surfaceY = _sy(world.lavaY);
    if (surfaceY > size.height + 40) return; // lava not visible yet

    final top = surfaceY.clamp(-40.0, size.height);
    final rect = Rect.fromLTWH(0, top, size.width, size.height - top + 40);

    final body = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE45C), Color(0xFFFF6A00), Color(0xFFD81E00)],
        stops: [0.0, 0.35, 1.0],
      ).createShader(rect);

    // Wavy top edge.
    final path = Path()..moveTo(0, top);
    const seg = 24.0;
    for (double x = 0; x <= size.width; x += seg) {
      final wave = math.sin((x / 60) + world.time * 4) * 7;
      path.lineTo(x, top + wave);
    }
    path.lineTo(size.width, size.height + 40);
    path.lineTo(0, size.height + 40);
    path.close();

    // Glow above the surface.
    canvas.drawRect(
      Rect.fromLTWH(0, top - 60, size.width, 80),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, top - 60),
          Offset(0, top + 20),
          [const Color(0x00FF6A00), const Color(0x66FF8A00)],
        ),
    );
    canvas.drawPath(path, body);

    // Bright rim on the wave crest.
    final rim = Paint()
      ..color = const Color(0xFFFFF0A0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);
    final crest = Path()..moveTo(0, top);
    for (double x = 0; x <= size.width; x += seg) {
      final wave = math.sin((x / 60) + world.time * 4) * 7;
      crest.lineTo(x, top + wave);
    }
    canvas.drawPath(crest, rim);

    // Bubbles.
    final bubble = Paint()..color = const Color(0x88FFD36B);
    for (int i = 0; i < 6; i++) {
      final bx = (i * 137.0 + world.time * 40 * (i.isEven ? 1 : -1)) % size.width;
      final phase = (world.time * 1.5 + i) % 2.2;
      final by = top + 24 + phase * 40;
      final r = 5 + (i % 3) * 2.0;
      canvas.drawCircle(Offset(bx.abs(), by), r, bubble);
    }
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
