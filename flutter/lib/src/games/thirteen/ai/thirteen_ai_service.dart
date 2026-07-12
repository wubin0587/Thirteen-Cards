import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../../backend/onnx_helper.dart';
import '../../../backend/onnx_worker_client.dart';
import '../../../backend/thirteen/thirteen_ffi.dart';
import '../../../models/ai_decision.dart';
import '../pile_position.dart';

typedef ThirteenFallback = Map<String, dynamic> Function();

/// Production thirteen-cards policy.
///
/// The native DLL owns candidate generation and validation. ONNX only selects
/// one of those candidates, matching `python/individual.py`.
class ThirteenAiService {
  ThirteenAiService({OnnxRuntime? runtime, OnnxWorkerClient? worker})
      : _runtime = runtime ?? OnnxRuntime.instance,
        _worker = worker ?? OnnxWorkerClient.instance;

  static const modelName = 'thirteen_ranker.onnx';
  final OnnxRuntime _runtime;
  final OnnxWorkerClient _worker;

  Future<AiDecision<Map<String, dynamic>>> recommend({
    required List<int> hand,
    required double temperature,
    required double aggression,
    required ThirteenFallback fallback,
  }) async {
    if (hand.length != 13) {
      throw ArgumentError.value(hand.length, 'hand.length', 'must be 13');
    }
    if (!_runtime.hasModel(modelName)) {
      return AiDecision(
        value: fallback(),
        source: AiDecisionSource.nativeFallback,
        error: StateError(
          '$modelName is not loaded',
        ),
      );
    }

    final handBuffer = calloc<Int32>(13);
    final result = calloc<TcDfsCandidateResult>();
    final bestIndex = calloc<Int32>();
    final logits = calloc<Float>(OnnxRuntime.tcMaxCombos);
    final handTokens = calloc<Float>(13 * OnnxRuntime.tcCardDim);
    final features = calloc<Float>(
      OnnxRuntime.tcMaxCombos * OnnxRuntime.tcComboDim,
    );
    final mask = calloc<Float>(OnnxRuntime.tcMaxCombos);
    try {
      for (var i = 0; i < hand.length; i++) handBuffer[i] = hand[i];
      final dfsRc = ThirteenCardsFfi.dfsEnumCombosRaw(
        handBuffer,
        result,
        OnnxRuntime.tcMaxCombos,
      );
      if (dfsRc != 0) throw StateError('tc_dfs_enum_combos failed: $dfsRc');

      if (result.ref.isSpecial != 0) {
        return AiDecision(
          value: fallback(),
          source: AiDecisionSource.nativeFallback,
          model: modelName,
        );
      }
      _runtime.tcEncodeHand(handBuffer, handTokens);
      final valid = _runtime.tcEncodeCombos(
        handBuffer,
        result.cast<Void>(),
        features,
        mask,
      );
      if (valid <= 0) throw StateError('no valid thirteen-card candidates');
      final output = await _worker.run(
        model: modelName,
        inputs: {
          'hand_tokens': Float32List.fromList(
            handTokens.asTypedList(13 * OnnxRuntime.tcCardDim),
          ),
          'combo_features': Float32List.fromList(
            features.asTypedList(
              OnnxRuntime.tcMaxCombos * OnnxRuntime.tcComboDim,
            ),
          ),
          'combo_mask': Float32List.fromList(
            mask.asTypedList(OnnxRuntime.tcMaxCombos),
          ),
        },
        inputShapes: const {
          'hand_tokens': [1, 13, OnnxRuntime.tcCardDim],
          'combo_features': [
            1,
            OnnxRuntime.tcMaxCombos,
            OnnxRuntime.tcComboDim,
          ],
          'combo_mask': [1, OnnxRuntime.tcMaxCombos],
        },
        outputSizes: const {'logits': OnnxRuntime.tcMaxCombos},
      );
      logits.asTypedList(OnnxRuntime.tcMaxCombos).setAll(0, output['logits']!);
      final rc = _runtime.tcSelect(
        result.cast<Void>(),
        logits,
        temperature.clamp(0.01, 10.0),
        aggression.clamp(-1.0, 1.0),
        bestIndex,
      );
      if (rc != 0) throw StateError('oh_tc_select failed: $rc');

      final arrangement = buildArrangement(result.ref, bestIndex.value);
      if (arrangement == null) {
        throw StateError('model selected an unassignable candidate');
      }
      // 把 combo index 传出去让 controller 做 DLL 验证
      (arrangement as Map)['_combo_index'] = bestIndex.value;
      return AiDecision(
        value: arrangement,
        source: AiDecisionSource.onnx,
        model: modelName,
      );
    } catch (error) {
      return AiDecision(
        value: fallback(),
        source: AiDecisionSource.nativeFallback,
        model: modelName,
        error: error,
      );
    } finally {
      calloc.free(handBuffer);
      calloc.free(result);
      calloc.free(bestIndex);
      calloc.free(logits);
      calloc.free(handTokens);
      calloc.free(features);
      calloc.free(mask);
    }
  }

  /// 从 DFS 结果中构建三墩（仅摆牌，不作验证）。
  /// 验证由 controller 通过 DLL 的 arrangementStatus 完成。
  Map<String, dynamic>? buildArrangement(TcDfsCandidateResult result, int comboIndex) {
    if (comboIndex < 0 || comboIndex >= result.comboCount) return null;
    final combo = result.combos[comboIndex];
    final threes = <List<int>>[];
    final fives = <({List<int> cards, int rank})>[];
    for (var i = 0; i < combo.unitCount.clamp(0, 3); i++) {
      final unit = combo.units[i];
      final cards = [for (var j = 0; j < unit.cardCount; j++) unit.cards[j]];
      if (cards.length == 3) threes.add(cards);
      if (cards.length == 5) {
        fives.add((cards: cards, rank: unit.result.rankOrder));
      }
    }
    fives.sort((a, b) => a.rank.compareTo(b.rank));
    var loose = [
      for (var i = 0; i < combo.looseCount.clamp(0, 13); i++) combo.looseCards[i],
    ]..sort((a, b) => _rank(b).compareTo(_rank(a)));

    final head = threes.isNotEmpty ? threes.first : _take(loose, 3);
    if (threes.isEmpty) loose = loose.skip(3).toList();
    final middle = fives.isNotEmpty ? fives.first.cards : _take(loose, 5);
    if (fives.isEmpty) loose = loose.skip(5).toList();
    final tail = fives.length >= 2 ? fives[1].cards : _take(loose, 5);
    if (head.length != 3 || middle.length != 5 || tail.length != 5) return null;

    final piles = <List<int>>[head, middle, tail];
    final map = <String, dynamic>{'is_special': false};
    for (final p in PilePosition.values) {
      map[p.key] = _pile(piles[p.positionIndex], ThirteenCardsFfi.searchPattern(p.positionIndex, piles[p.positionIndex]));
    }
    return map;
  }

  static int _rank(int card) => (card % 52) ~/ 4;
  static List<int> _take(List<int> cards, int count) =>
      cards.take(count).toList(growable: false);

  static Map<String, dynamic> _pile(
    List<int> cards,
    Map<String, dynamic> result,
  ) =>
      {
        'cards': cards,
        'name': result['hand_name'],
        'score': result['score'],
        'rank_order': result['rank_order'],
      };
}
