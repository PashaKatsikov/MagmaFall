import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:magmafall/game/game_world.dart';

void main() {
  test('A fresh world starts ready to play', () {
    final world = GameWorld(size: const Size(400, 800));
    expect(world.status, GameStatus.playing);
    expect(world.score, 0);
    expect(world.platforms, isNotEmpty);
  });

  test('The player is kept on screen while following the finger', () {
    final world = GameWorld(size: const Size(400, 800));
    world.touchAt(9999); // way off the right edge
    for (var i = 0; i < 30; i++) {
      world.update(1 / 60);
    }
    expect(world.player.x, lessThanOrEqualTo(400 - GameWorld.playerHalf));
    expect(world.player.x, greaterThanOrEqualTo(GameWorld.playerHalf));
  });

  test('Simulating the game never throws and keeps score non-negative', () {
    final world = GameWorld(size: const Size(400, 800));
    for (var i = 0; i < 600; i++) {
      world.update(1 / 60);
    }
    expect(world.score, greaterThanOrEqualTo(0));
    expect(world.highestY, lessThanOrEqualTo(0));
  });
}
