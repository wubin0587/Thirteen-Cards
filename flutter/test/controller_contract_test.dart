import 'package:flutter_test/flutter_test.dart';

import '../lib/src/games/thirteen/controller/thirteen_controller.dart';
import '../lib/src/games/thirteen/ai/thirteen_style.dart';
import '../lib/src/models/ai_decision.dart';

/// 启动原生引擎测试需要先编译:
///   thirteen_cards_cpp.dll (from ../cpp)
///   onnx_thirteen.dll     (from ../src/onnx_thirteen.c)
void main() {
  test('thirteen controller owns its session and returns a valid fallback',
      () async {
    final controller = ThirteenController(playerCount: 4);
    addTearDown(controller.dispose);

    controller.startRound();
    expect(controller.hands, hasLength(4));
    expect(controller.hands.every((hand) => hand.length == 13), isTrue);

    final decision = await controller.recommend(AiStyle.balanced);
    expect(decision.source, AiDecisionSource.nativeFallback);
    expect((decision.value['head'] as Map)['cards'], hasLength(3));
    expect((decision.value['middle'] as Map)['cards'], hasLength(5));
    expect((decision.value['tail'] as Map)['cards'], hasLength(5));
  });
}
