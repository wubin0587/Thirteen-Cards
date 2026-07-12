import 'package:flutter/foundation.dart';

import '../../../backend/app_settings.dart';
import '../../../backend/thirteen/thirteen_ffi.dart';
import '../../../models/ai_decision.dart';
import '../ai/thirteen_ai_service.dart';
import '../ai/thirteen_style.dart';
import '../pile_position.dart';

class ThirteenController extends ChangeNotifier {
  ThirteenController({
    required this.playerCount,
    ThirteenAiService? ai,
  }) : _ai = ai ?? ThirteenAiService() {
    _native = ThirteenGameSession(playerCount: playerCount);
  }

  final int playerCount;
  final ThirteenAiService _ai;
  late ThirteenGameSession _native;

  ThirteenGameSession get native => _native;
  List<List<int>> hands = const [];
  bool busy = false;
  Object? lastError;

  void startRound() {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      if (_native.phase != 0 && _native.phase != 3) {
        _native.dispose();
        _native = ThirteenGameSession(playerCount: playerCount);
      }
      _native.startRound();
      hands = [for (var i = 0; i < playerCount; i++) _native.hand(i)];
    } catch (error) {
      lastError = error;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<AiDecision<Map<String, dynamic>>> recommend([AiStyle style = AiStyle.balanced]) async {
    if (hands.isEmpty) throw StateError('no hand dealt — call startRound() first');
    final hand = hands.first;
    final decision = await _ai.recommend(
      hand: hand,
      temperature: AppSettings.difficulty,
      aggression: style.aggression,
      fallback: () => _nativeRecommendation(),
    );
    if (decision.error != null) {
      debugPrint('thirteen_controller: AI recommend error (fallback used): ${decision.error}');
    }
    if (decision.source == AiDecisionSource.nativeFallback) return decision;

    // 用 DLL 验证摆牌是否合法
    final arr = decision.value;
    final applyMap = <String, List<int>>{
      for (final p in PilePosition.values)
        p.key: ((arr[p.key] as Map)['cards'] as List<dynamic>).cast<int>(),
    };
    _native.apply(0, {
      'is_special': false,
      ...applyMap,
    });
    final status = _native.arrangementStatus(0);

    if (status == 1) return decision; // DLL 验证通过
    // DLL 判定倒水 → 重新应用 native 方案覆盖
    final fallback = _nativeRecommendation();
    final fallbackMap = <String, List<int>>{
      for (final p in PilePosition.values)
        p.key: ((fallback[p.key] as Map)['cards'] as List<dynamic>).cast<int>(),
    };
    _native.apply(0, {
      'is_special': false,
      ...fallbackMap,
    });
    return AiDecision(
      value: fallback,
      source: AiDecisionSource.nativeFallback,
      model: decision.model,
    );
  }

  Map<String, dynamic> _nativeRecommendation() {
    final arrangement = _native.recommend(0, 0);
    final special = arrangement['special_result'] as Map<String, dynamic>;

    final map = <String, dynamic>{
      'is_special': arrangement['is_special'] == true,
      if (arrangement['is_special'] == true)
        'detected_special_name': special['hand_name'],
      if (arrangement['is_special'] == true)
        'detected_special_score': special['score'],
    };
    for (final p in PilePosition.values) {
      final result = arrangement['${p.key}_result'] as Map<String, dynamic>;
      map[p.key] = {
        'cards': (arrangement[p.key] as List<dynamic>).cast<int>(),
        'name': result['hand_name'],
        'score': result['score'],
        'rank_order': result['rank_order'],
      };
    }
    return map;
  }

  @override
  void dispose() {
    _native.dispose();
    super.dispose();
  }
}
