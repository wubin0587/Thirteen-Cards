import 'package:flutter_test/flutter_test.dart';

import '../lib/src/backend/thirteen/thirteen_ffi.dart';

void main() {
  test('thirteen round is owned and settled by the native state machine', () {
    final game = ThirteenGameSession(playerCount: 4);
    addTearDown(game.dispose);

    expect(game.phase, 0);
    game.startRound();
    expect(game.phase, 1);
    for (var player = 0; player < 4; player++) {
      expect(game.hand(player), hasLength(13));
      game.autoArrange(player, 0);
    }
    game.settle();
    expect(game.phase, 3);
    expect(game.pairSettlements(), hasLength(6));
    expect(
      [for (var player = 0; player < 4; player++) game.playerSettlement(player)],
      hasLength(4),
    );
  });

}
