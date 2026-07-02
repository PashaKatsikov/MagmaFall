import 'dart:math' as math;
import 'dart:ui';

import 'entities.dart';

enum GameStatus { playing, lost }

double _lerp(double a, double b, double t) => a + (b - a) * t;

class GameWorld {
  GameWorld({required this.size}) : rng = math.Random() {
    _reset();
  }

  Size size;
  final math.Random rng;

  // ---- Physics ----
  static const double gravity = 2500;
  static const double jumpVelocity = -1180;
  static const double bouncyVelocity = -2050;
  static const double playerHalf = 30;
  static const double footOffset = 30;

  /// Max horizontal speed in pixels/sec.
  static const double maxHSpeed = 520;

  static const double difficultyRange = 26000;

  // ---- Entities ----
  late Player player;
  final List<GamePlatform> platforms = [];
  final List<Bat> bats = [];
  final List<Meteor> meteors = [];

  // ---- State ----
  double cameraY = 0;
  double lavaY = 0;
  double highestY = 0;
  double topSpawnedY = 0;
  double nextBatY = 0;
  double meteorTimer = 0;
  double time = 0;
  GameStatus status = GameStatus.playing;

  // ---- Doodle-Jump style input ----
  // -1 = full left, 0 = stopped, +1 = full right.
  double _inputDir = 0.0;

  /// Call every frame the finger is on screen with its X position.
  void touchAt(double localX) {
    final halfW = size.width / 2;
    _inputDir = ((localX - halfW) / halfW).clamp(-1.0, 1.0);
  }

  /// Call when the finger is lifted.
  void releaseTouch() => _inputDir = 0.0;

  double get worldWidth => size.width;
  double get climb => -highestY;
  int get score => (climb / 10).floor();
  double get _difficulty => (climb / difficultyRange).clamp(0.0, 1.0);

  void _reset() {
    player = Player(x: size.width / 2, y: 0);
    player.vy = jumpVelocity;
    platforms.clear();
    bats.clear();
    meteors.clear();
    cameraY = player.y - size.height * 0.45;
    lavaY = 900;
    highestY = 0;
    topSpawnedY = 120;
    nextBatY = -1200;
    meteorTimer = 6;
    time = 0;
    status = GameStatus.playing;
    _inputDir = 0.0;

    platforms.add(GamePlatform(
      x: size.width / 2 - 75,
      y: 120,
      width: 150,
      type: PlatformType.normal,
    ));
    _fillPlatformsAbove();
  }

  void resize(Size newSize) => size = newSize;

  // ---------------------------------------------------------------------------
  void update(double dt) {
    if (status != GameStatus.playing) return;
    dt = dt.clamp(0.0, 1 / 30);
    time += dt;

    _updatePlayer(dt);
    _updatePlatforms(dt);
    _updateEnemies(dt);
    _updateCameraAndLava(dt);
    _fillPlatformsAbove();
    _cullOffscreen();
    _checkLose();
  }

  void _updatePlayer(double dt) {
    // Horizontal – Doodle Jump style: finger position relative to centre sets
    // velocity directly. Ice makes steering sluggish.
    if (_inputDir.abs() > 0.02) {
      final target = _inputDir * maxHSpeed;
      if (player.onIce) {
        // Gradually approach on ice.
        player.vx += (target - player.vx) * (1 - math.exp(-dt * 5));
      } else {
        player.vx = target; // Instant, snappy response.
      }
    } else {
      // No finger – brake.
      final brake = player.onIce ? 3.0 : 20.0;
      player.vx *= math.pow(math.e, -brake * dt).toDouble();
      if (player.vx.abs() < 4) player.vx = 0;
    }

    player.x += player.vx * dt;

    // Screen wrap like Doodle Jump.
    if (player.x < 0) player.x += worldWidth;
    if (player.x > worldWidth) player.x -= worldWidth;

    if (player.vx.abs() > 20) player.facingRight = player.vx > 0;

    // Vertical.
    player.vy += gravity * dt;
    final oldY = player.y;
    player.y += player.vy * dt;
    if (player.squashTimer > 0) player.squashTimer -= dt;

    player.onIce = false;
    if (player.vy > 0) _resolvePlatformLanding(oldY);

    if (player.y < highestY) highestY = player.y;
  }

  void _resolvePlatformLanding(double oldY) {
    final feetOld = oldY + footOffset;
    final feetNew = player.y + footOffset;

    GamePlatform? landed;
    for (final p in platforms) {
      if (p.broken) continue;
      final top = p.y;
      if (feetOld <= top + 4 && feetNew >= top) {
        if ((player.x - p.centerX).abs() <= p.width / 2 + 6) {
          landed = p;
          break;
        }
      }
    }
    if (landed == null) return;

    player.y = landed.y - footOffset;
    player.squashTimer = 0.18;

    switch (landed.type) {
      case PlatformType.bouncy:
        player.vy = bouncyVelocity;
        break;
      case PlatformType.cracked:
      case PlatformType.cloud:
        player.vy = jumpVelocity;
        landed.broken = true;
        break;
      case PlatformType.icy:
        player.vy = jumpVelocity;
        player.onIce = true;
        break;
      case PlatformType.normal:
      case PlatformType.moving:
        player.vy = jumpVelocity;
        break;
    }
  }

  void _updatePlatforms(double dt) {
    final movingSpeed = _lerp(70, 150, _difficulty);
    for (final p in platforms) {
      if (p.type == PlatformType.moving && !p.broken) {
        p.x += p.dir * movingSpeed * dt;
        if (p.x <= p.minX) { p.x = p.minX; p.dir = 1; }
        else if (p.x >= p.maxX) { p.x = p.maxX; p.dir = -1; }
      }
      if (p.broken) {
        p.breakTimer += dt;
        p.y += 900 * p.breakTimer * dt * 6;
      }
    }
    platforms.removeWhere((p) => p.broken && p.breakTimer > 0.5);
  }

  void _updateEnemies(double dt) {
    final t = _difficulty;
    if (climb > 1000) {
      final spacing = _lerp(1500, 620, t);
      while (highestY < nextBatY) {
        _spawnBat(nextBatY - 40);
        nextBatY -= spacing;
      }
    }
    for (final b in bats) {
      b.x += b.dir * b.speed * dt;
      b.wing += dt * 12;
      if (b.x < 40) { b.x = 40; b.dir = 1; }
      else if (b.x > worldWidth - 40) { b.x = worldWidth - 40; b.dir = -1; }
      if (_hitPlayer(b.x, b.y, 34)) status = GameStatus.lost;
    }
    if (climb > 3500) {
      meteorTimer -= dt;
      if (meteorTimer <= 0) {
        meteorTimer = _lerp(6.0, 2.0, t) * (0.7 + rng.nextDouble() * 0.6);
        meteors.add(Meteor(
          x: 40 + rng.nextDouble() * (worldWidth - 80),
          y: cameraY - 80,
          vy: 520 + rng.nextDouble() * 260,
        ));
      }
    }
    for (final m in meteors) {
      m.y += m.vy * dt;
      m.spin += dt * 6;
      if (_hitPlayer(m.x, m.y, 30)) status = GameStatus.lost;
    }
    meteors.removeWhere((m) => m.y > cameraY + size.height + 120);
  }

  bool _hitPlayer(double x, double y, double r) {
    final dx = x - player.x;
    final dy = y - player.y;
    final rr = r + playerHalf * 0.7;
    return dx * dx + dy * dy < rr * rr;
  }

  void _updateCameraAndLava(double dt) {
    final target = player.y - size.height * 0.45;
    if (target < cameraY) cameraY = target;
    lavaY -= _lerp(70, 260, _difficulty) * dt;
  }

  void _fillPlatformsAbove() {
    final ceiling = cameraY - size.height * 0.6;
    while (topSpawnedY > ceiling) {
      final t = (-topSpawnedY / difficultyRange).clamp(0.0, 1.0);
      final minGap = _lerp(112, 150, t);
      final maxGap = _lerp(170, 234, t);
      final gap = minGap + rng.nextDouble() * (maxGap - minGap);
      topSpawnedY -= gap;
      final base = _makePlatform(topSpawnedY, t);
      platforms.add(base);
      _tryPlaceMushroom(base, t);
    }
  }

  /// Possibly add a bouncy mushroom sitting ON TOP of [base].
  /// The mushroom is never spawned floating in the air – always anchored to a
  /// platform.  It must not appear on cracked/cloud platforms (they vanish).
  void _tryPlaceMushroom(GamePlatform base, double t) {
    if (base.type == PlatformType.cracked || base.type == PlatformType.cloud) {
      return;
    }
    // Probability rises slightly with difficulty.
    if (rng.nextDouble() >= _lerp(0.12, 0.18, t)) return;

    // Mushroom collision width – narrower than the base.
    final mWidth = (base.width * 0.55).clamp(38.0, 78.0);

    // Place the mushroom's surface (p.y = where the player bounces) so that
    // the bottom edge of the sprite lands ~2 px inside the base platform top
    // surface.  anchor = 0.74 means 26 % of drawHeight hangs below p.y.
    // drawHeight ≈ mWidth * 1.15 * aspectRatio.  We approximate it at 0.88.
    const anchor = 0.74;
    final drawH = mWidth * 1.15 * 0.88; // estimated draw height
    // bottom of sprite = p.y + (1 - anchor) * drawH
    // target bottom    = base.y + 2  (slightly inside the base platform)
    final mY = base.y + 2 - (1 - anchor) * drawH; // < base.y (higher in world)

    // Centre horizontally on the base with a small random nudge.
    final maxShift = (base.width - mWidth) / 2 * 0.7;
    final nudge = (rng.nextDouble() * 2 - 1) * maxShift;
    final mX = (base.centerX + nudge - mWidth / 2)
        .clamp(8.0, worldWidth - mWidth - 8);

    platforms.add(GamePlatform(
      x: mX,
      y: mY,
      width: mWidth,
      type: PlatformType.bouncy,
    ));
  }

  GamePlatform _makePlatform(double y, double t) {
    // Bouncy platforms are placed separately via _tryPlaceMushroom.
    var width = _lerp(150, 96, t);
    final roll = rng.nextDouble();
    var acc = 0.0;
    PlatformType type = PlatformType.normal;
    if (roll < (acc += _lerp(0.0, 0.32, t))) {
      type = PlatformType.moving;
    } else if (roll < (acc += _lerp(0.0, 0.26, t))) {
      type = PlatformType.cracked;
    } else if (roll < (acc += _lerp(0.0, 0.20, t))) {
      type = PlatformType.cloud;
    } else if (roll < (acc += _lerp(0.0, 0.20, t))) {
      type = PlatformType.icy;
    }
    final maxLeft = (worldWidth - width - 12).clamp(12.0, double.infinity);
    final x = 12 + rng.nextDouble() * (maxLeft - 12);
    final p = GamePlatform(x: x, y: y, width: width, type: type);
    if (type == PlatformType.moving) {
      p.minX = 12;
      p.maxX = worldWidth - width - 12;
      p.dir = rng.nextBool() ? 1 : -1;
    }
    return p;
  }

  void _spawnBat(double y) {
    final fromLeft = rng.nextBool();
    bats.add(Bat(
      x: fromLeft ? 40 : worldWidth - 40,
      y: y,
      dir: fromLeft ? 1 : -1,
      speed: _lerp(80, 165, _difficulty),
    ));
  }

  void _cullOffscreen() {
    final floor = cameraY + size.height + 260;
    platforms.removeWhere((p) => p.y > floor);
    bats.removeWhere((b) => b.y > floor);
  }

  void _checkLose() {
    final feet = player.y + footOffset;
    final fellBelowView = (player.y - cameraY) > size.height + 60;
    if (feet >= lavaY || fellBelowView) status = GameStatus.lost;
  }
}

class Player {
  Player({required this.x, required this.y});
  double x;
  double y;
  double vx = 0;
  double vy = 0;
  bool facingRight = true;
  bool onIce = false;
  double squashTimer = 0;

  bool get falling => vy > 60;
  bool get squashed => squashTimer > 0;
}
