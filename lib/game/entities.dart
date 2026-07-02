import 'dart:ui';

enum PlatformType { normal, moving, cracked, cloud, icy, bouncy }

/// A stone platform the player bounces on. Some types have special behaviour.
class GamePlatform {
  GamePlatform({
    required this.x,
    required this.y,
    required this.width,
    required this.type,
    this.minX = 0,
    this.maxX = 0,
    this.dir = 1,
  });

  /// Left edge (world coords).
  double x;

  /// Top solid surface (world coords, y grows downward).
  double y;
  double width;
  PlatformType type;

  // Movement bounds for [PlatformType.moving].
  double minX;
  double maxX;
  double dir;

  /// Once a fragile platform (cracked / cloud) is used it breaks apart.
  bool broken = false;
  double breakTimer = 0;

  double get centerX => x + width / 2;
  Rect get surface => Rect.fromLTWH(x, y, width, 18);
}

/// A flying bat enemy that patrols horizontally. Touching it is fatal.
class Bat {
  Bat({required this.x, required this.y, required this.dir, required this.speed});
  double x;
  double y;
  double dir;
  double speed;
  double wing = 0;
}

/// A meteor that falls from the top of the screen. Touching it is fatal.
class Meteor {
  Meteor({required this.x, required this.y, required this.vy});
  double x;
  double y;
  double vy;
  double spin = 0;
}
