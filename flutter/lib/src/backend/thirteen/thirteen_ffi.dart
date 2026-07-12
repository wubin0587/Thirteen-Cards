import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

final class TcGameHandResult extends Struct {
  @Int32()
  external int position;
  @Int32()
  external int rankOrder;
  @Int32()
  external int score;
  @Array(48)
  external Array<Uint8> handName;
}

/// Complete-table state machine. No game rule is evaluated in Dart.
final class ThirteenGameSession {
  ThirteenGameSession({required this.playerCount}) {
    final lib = ThirteenCardsFfi.lib;
    _create = lib.lookupFunction<Pointer<Void> Function(Int32),
        Pointer<Void> Function(int)>('tc_game_create');
    _destroy = lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('tc_game_destroy');
    _start = lib.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('tc_game_start_round');
    _phase = lib.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('tc_game_get_phase');
    _getHand = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Pointer<Int32>),
        int Function(Pointer<Void>, int, Pointer<Int32>)>('tc_game_get_hand');
    _getPile = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Int32, Pointer<Int32>, Int32),
        int Function(
            Pointer<Void>, int, int, Pointer<Int32>, int)>('tc_game_get_pile');
    _getStatus = lib.lookupFunction<Int32 Function(Pointer<Void>, Int32, Int32),
        int Function(Pointer<Void>, int, int)>('tc_game_get_card_status');
    _arrangementStatus = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)>('tc_game_get_arrangement_status');
    _select = lib.lookupFunction<Int32 Function(Pointer<Void>, Int32, Int32),
        int Function(Pointer<Void>, int, int)>('tc_game_select_card');
    _deselect = lib.lookupFunction<Int32 Function(Pointer<Void>, Int32, Int32),
        int Function(Pointer<Void>, int, int)>('tc_game_deselect_card');
    _add = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Int32, Int32),
        int Function(Pointer<Void>, int, int, int)>('tc_game_add_to_pile');
    _remove = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Int32, Int32),
        int Function(Pointer<Void>, int, int, int)>('tc_game_remove_from_pile');
    _undo = lib.lookupFunction<Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)>('tc_game_undo');
    _recommend = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Int32, Pointer<TcGameArrangement>),
        int Function(Pointer<Void>, int, int,
            Pointer<TcGameArrangement>)>('tc_game_recommend_arrangement');
    _apply = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Pointer<TcGameArrangement>),
        int Function(Pointer<Void>, int,
            Pointer<TcGameArrangement>)>('tc_game_apply_arrangement');
    _autoArrange = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Int32),
        int Function(Pointer<Void>, int, int)>('tc_game_auto_arrange');
    _submit = lib.lookupFunction<Int32 Function(Pointer<Void>, Int32, Int32),
        int Function(Pointer<Void>, int, int)>('tc_game_submit_arrangement');
    _settle = lib.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('tc_game_settle');
    _getPlayerSettlement = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Pointer<TcGamePlayerSettlement>),
        int Function(Pointer<Void>, int,
            Pointer<TcGamePlayerSettlement>)>('tc_game_get_player_settlement');
    _pairCount = lib.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('tc_game_get_pair_count');
    _getPair = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Pointer<TcGamePairSettlement>),
        int Function(Pointer<Void>, int,
            Pointer<TcGamePairSettlement>)>('tc_game_get_pair_settlement');
    _isSpecial = lib.lookupFunction<Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)>('tc_game_is_special');
    _getSpecialResult = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Pointer<TcGameHandResult>),
        int Function(Pointer<Void>, int,
            Pointer<TcGameHandResult>)>('tc_game_get_special_result');
    _handle = _create(playerCount);
    if (_handle == nullptr) throw StateError('tc_game_create failed');
  }

  final int playerCount;
  late Pointer<Void> _handle;
  late final Pointer<Void> Function(int) _create;
  late final void Function(Pointer<Void>) _destroy;
  late final int Function(Pointer<Void>) _start, _phase, _settle, _pairCount;
  late final int Function(Pointer<Void>, int, Pointer<Int32>) _getHand;
  late final int Function(Pointer<Void>, int, int, Pointer<Int32>, int)
      _getPile;
  late final int Function(Pointer<Void>, int, int) _getStatus,
      _select,
      _deselect;
  late final int Function(Pointer<Void>, int) _undo, _arrangementStatus;
  late final int Function(Pointer<Void>, int, int, int) _add, _remove;
  late final int Function(Pointer<Void>, int, int, Pointer<TcGameArrangement>)
      _recommend;
  late final int Function(Pointer<Void>, int, Pointer<TcGameArrangement>)
      _apply;
  late final int Function(Pointer<Void>, int, int) _autoArrange, _submit;
  late final int Function(Pointer<Void>, int, Pointer<TcGamePlayerSettlement>)
      _getPlayerSettlement;
  late final int Function(Pointer<Void>, int, Pointer<TcGamePairSettlement>)
      _getPair;
  late final int Function(Pointer<Void>, int) _isSpecial;
  late final int Function(Pointer<Void>, int, Pointer<TcGameHandResult>)
      _getSpecialResult;
  final Pointer<Int32> _cards = calloc<Int32>(13);
  bool _disposed = false;

  void _check(int rc, String operation) {
    if (rc < 0) throw StateError('$operation failed: $rc');
  }

  int get phase => _phase(_handle);
  void startRound() => _check(_start(_handle), 'tc_game_start_round');
  List<int> hand(int player) {
    _check(_getHand(_handle, player, _cards), 'tc_game_get_hand');
    return [for (var i = 0; i < 13; i++) _cards[i]];
  }

  List<int> pile(int player, int position) {
    final n = _getPile(_handle, player, position, _cards, 13);
    _check(n, 'tc_game_get_pile');
    return [for (var i = 0; i < n; i++) _cards[i]];
  }

  int cardStatus(int player, int index) => _getStatus(_handle, player, index);
  int arrangementStatus(int player) => _arrangementStatus(_handle, player);
  bool isSpecial(int player) => _isSpecial(_handle, player) != 0;
  ({String name, int score}) getSpecialResult(int player) {
    final out = calloc<TcGameHandResult>();
    try {
      _check(_getSpecialResult(_handle, player, out),
          'tc_game_get_special_result');
      return (
        name: _tcFixedString(out.ref.handName, 48),
        score: out.ref.score,
      );
    } finally {
      calloc.free(out);
    }
  }
  void select(int p, int i) =>
      _check(_select(_handle, p, i), 'tc_game_select_card');
  void deselect(int p, int i) =>
      _check(_deselect(_handle, p, i), 'tc_game_deselect_card');
  void addToPile(int p, int pos, int i) =>
      _check(_add(_handle, p, pos, i), 'tc_game_add_to_pile');
  void removeFromPile(int p, int pos, int i) =>
      _check(_remove(_handle, p, pos, i), 'tc_game_remove_from_pile');
  void undo(int p) => _check(_undo(_handle, p), 'tc_game_undo');
  Map<String, dynamic> recommend(int p, int strategy) {
    final out = calloc<TcGameArrangement>();
    try {
      _check(_recommend(_handle, p, strategy, out),
          'tc_game_recommend_arrangement');
      return _arrangementMap(out.ref);
    } finally {
      calloc.free(out);
    }
  }

  void apply(int p, Map<String, dynamic> value) {
    final a = calloc<TcGameArrangement>();
    try {
      _writeArrangement(a.ref, value);
      _check(_apply(_handle, p, a), 'tc_game_apply_arrangement');
    } finally {
      calloc.free(a);
    }
  }

  void autoArrange(int p, int strategy) =>
      _check(_autoArrange(_handle, p, strategy), 'tc_game_auto_arrange');
  void submit(int p, {bool allowFouled = false}) => _check(
      _submit(_handle, p, allowFouled ? 1 : 0), 'tc_game_submit_arrangement');
  void settle() => _check(_settle(_handle), 'tc_game_settle');
  Map<String, dynamic> playerSettlement(int p) {
    final out = calloc<TcGamePlayerSettlement>();
    try {
      _check(_getPlayerSettlement(_handle, p, out),
          'tc_game_get_player_settlement');
      final v = out.ref;
      return {
        'player': v.playerIndex,
        'hand': [for (var i = 0; i < 13; i++) v.hand[i]],
        'head': [for (var i = 0; i < 3; i++) v.head[i]],
        'middle': [for (var i = 0; i < 5; i++) v.middle[i]],
        'tail': [for (var i = 0; i < 5; i++) v.tail[i]],
        'head_result': _tcResultMap(v.headResult),
        'middle_result': _tcResultMap(v.middleResult),
        'tail_result': _tcResultMap(v.tailResult),
        'special_result': _tcResultMap(v.specialResult),
        'is_special': v.isSpecial != 0,
        'fouled': v.fouled != 0,
        'homerun': v.homerun != 0,
        'shoot_count': v.shootCount,
        'shot_count': v.shotCount,
        'net': v.roundNetScore,
        'total': v.totalScore,
        'achievements': v.achievements,
      };
    } finally {
      calloc.free(out);
    }
  }

  List<Map<String, dynamic>> pairSettlements() {
    final n = _pairCount(_handle);
    _check(n, 'tc_game_get_pair_count');
    final out = calloc<TcGamePairSettlement>();
    try {
      return [
        for (var i = 0; i < n; i++)
          ...() {
            _check(_getPair(_handle, i, out), 'tc_game_get_pair_settlement');
            final v = out.ref;
            return [
              {
                'a': v.playerA,
                'b': v.playerB,
                'head_cmp': v.headCmp,
                'middle_cmp': v.middleCmp,
                'tail_cmp': v.tailCmp,
                'winner': v.winner,
                'base_score': v.baseScore,
                'multiplier': v.multiplier,
                'final_score': v.finalScore,
                'shoot_a': v.shootA != 0,
                'shoot_b': v.shootB != 0
              }
            ];
          }()
      ];
    } finally {
      calloc.free(out);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_handle);
    _handle = nullptr;
    calloc.free(_cards);
  }

  static Map<String, dynamic> _arrangementMap(TcGameArrangement v) => {
        'is_special': v.isSpecial != 0,
        'head': [for (var i = 0; i < 3; i++) v.head[i]],
        'middle': [for (var i = 0; i < 5; i++) v.middle[i]],
        'tail': [for (var i = 0; i < 5; i++) v.tail[i]],
        'head_result': _tcResultMap(v.headResult),
        'middle_result': _tcResultMap(v.middleResult),
        'tail_result': _tcResultMap(v.tailResult),
        'special_result': _tcResultMap(v.specialResult),
        'utility_score': v.utilityScore
      };
  static void _writeArrangement(TcGameArrangement a, Map<String, dynamic> v) {
    a.isSpecial = v['is_special'] == true ? 1 : 0;
    final h = (v['head'] as List).cast<int>(),
        m = (v['middle'] as List).cast<int>(),
        t = (v['tail'] as List).cast<int>();
    for (var i = 0; i < 3; i++) a.head[i] = h[i];
    for (var i = 0; i < 5; i++) {
      a.middle[i] = m[i];
      a.tail[i] = t[i];
    }
  }
}

final class TcGameArrangement extends Struct {
  @Int32()
  external int isSpecial;
  @Array(3)
  external Array<Int32> head;
  @Array(5)
  external Array<Int32> middle;
  @Array(5)
  external Array<Int32> tail;
  external TcGameHandResult headResult;
  external TcGameHandResult middleResult;
  external TcGameHandResult tailResult;
  external TcGameHandResult specialResult;
  @Int32()
  external int utilityScore;
}

final class TcGamePlayerSettlement extends Struct {
  @Int32()
  external int playerIndex;
  @Array(13)
  external Array<Int32> hand;
  @Array(3)
  external Array<Int32> head;
  @Array(5)
  external Array<Int32> middle;
  @Array(5)
  external Array<Int32> tail;
  external TcGameHandResult headResult;
  external TcGameHandResult middleResult;
  external TcGameHandResult tailResult;
  external TcGameHandResult specialResult;
  @Int32()
  external int isSpecial;
  @Int32()
  external int fouled;
  @Int32()
  external int homerun;
  @Int32()
  external int shootCount;
  @Int32()
  external int shotCount;
  @Int32()
  external int roundNetScore;
  @Int32()
  external int totalScore;
  @Uint32()
  external int achievements;
}

final class TcGamePairSettlement extends Struct {
  @Int32()
  external int playerA;
  @Int32()
  external int playerB;
  @Int32()
  external int headCmp;
  @Int32()
  external int middleCmp;
  @Int32()
  external int tailCmp;
  @Int32()
  external int winner;
  @Int32()
  external int baseScore;
  @Int32()
  external int multiplier;
  @Int32()
  external int finalScore;
  @Int32()
  external int shootA;
  @Int32()
  external int shootB;
}

String _tcFixedString(Array<Uint8> chars, int capacity) {
  final bytes = <int>[];
  for (var i = 0; i < capacity && chars[i] != 0; i++) bytes.add(chars[i]);
  return String.fromCharCodes(bytes);
}

Map<String, dynamic> _tcResultMap(TcGameHandResult value) => {
      'position': value.position,
      'rank_order': value.rankOrder,
      'score': value.score,
      'hand_name': _tcFixedString(value.handName, 48),
    };

// ============================================================
//  C 结构体映射
// ============================================================

final class THandResult extends Struct {
  @Int32()
  external int position;

  external Pointer<Utf8> handName;

  @Int32()
  external int rankOrder;

  @Int32()
  external int score;
}

final class THandUnit extends Struct {
  @Int32()
  external int cardCount;

  @Array(5)
  external Array<Int32> cards;

  external THandResult result;
}

final class THandCombo extends Struct {
  @Int32()
  external int unitCount;

  @Array(3)
  external Array<THandUnit> units;

  @Int32()
  external int typedScore;

  @Int32()
  external int looseCount;

  @Array(13)
  external Array<Int32> looseCards;
}

final class TcDfsCandidateResult extends Struct {
  @Int32()
  external int isSpecial;

  @Int32()
  external int specialScore;

  external Pointer<Utf8> specialName;

  @Int32()
  external int comboCount;

  @Array(128)
  external Array<THandCombo> combos;
}

final class TPattern extends Struct {
  @Array(13)
  external Array<Int32> hand;

  @Array(3)
  external Array<Int32> head;

  @Array(5)
  external Array<Int32> middle;

  @Array(5)
  external Array<Int32> tail;
}

// ============================================================
//  Native 函数类型定义
// ============================================================

// 牌型检测
typedef TcSearchPatternC = THandResult Function(
    Int32 position, Pointer<Int32> cards, Int32 cnt);
typedef TcSearchPatternDart = THandResult Function(
    int position, Pointer<Int32> cards, int cnt);

// DFS 枚举
typedef TcDfsEnumCombosC = Int32 Function(
    Pointer<Int32> hand13, Pointer<TcDfsCandidateResult> out, Int32 maxK);
typedef TcDfsEnumCombosDart = int Function(
    Pointer<Int32> hand13, Pointer<TcDfsCandidateResult> out, int maxK);

// 牌比较
typedef TcCompareHead3C = Int32 Function(
    Pointer<Int32> cardsA, Pointer<Int32> cardsB);
typedef TcCompareHead3Dart = int Function(
    Pointer<Int32> cardsA, Pointer<Int32> cardsB);
typedef TcCompareFiveC = Int32 Function(
    Pointer<Int32> cardsA, Pointer<Int32> cardsB);
typedef TcCompareFiveDart = int Function(
    Pointer<Int32> cardsA, Pointer<Int32> cardsB);
typedef TcCompareHandResultC = Int32 Function(Int32 roA, Int32 roB);
typedef TcCompareHandResultDart = int Function(int roA, int roB);

// PlayerRound 生命周期
typedef TcPlayerRoundCreateC = Pointer<Void> Function(Pointer<Utf8> name);
typedef TcPlayerRoundCreateDart = Pointer<Void> Function(Pointer<Utf8> name);
typedef TcPlayerRoundDestroyC = Void Function(Pointer<Void> player);
typedef TcPlayerRoundDestroyDart = void Function(Pointer<Void> player);
typedef TcPlayerRoundReceiveHandC = Int32 Function(
    Pointer<Void> player, Pointer<Int32> hand13);
typedef TcPlayerRoundReceiveHandDart = int Function(
    Pointer<Void> player, Pointer<Int32> hand13);
typedef TcPlayerRoundSetPositionC = Int32 Function(
    Pointer<Void> player, Int32 position, Pointer<Int32> cards, Int32 cnt);
typedef TcPlayerRoundSetPositionDart = int Function(
    Pointer<Void> player, int position, Pointer<Int32> cards, int cnt);
typedef TcPlayerRoundSettleC = Int32 Function(Pointer<Void> player);
typedef TcPlayerRoundSettleDart = int Function(Pointer<Void> player);
typedef TcPlayerRoundGetHandC = Int32 Function(
    Pointer<Void> player, Pointer<Int32> outHand13);
typedef TcPlayerRoundGetHandDart = int Function(
    Pointer<Void> player, Pointer<Int32> outHand13);
typedef TcPlayerRoundGetRoundScoreC = Int32 Function(Pointer<Void> player);
typedef TcPlayerRoundGetRoundScoreDart = int Function(Pointer<Void> player);
typedef TcPlayerRoundGetTotalScoreC = Int32 Function(Pointer<Void> player);
typedef TcPlayerRoundGetTotalScoreDart = int Function(Pointer<Void> player);
typedef TcPlayerRoundGetNameC = Pointer<Utf8> Function(Pointer<Void> player);
typedef TcPlayerRoundGetNameDart = Pointer<Utf8> Function(Pointer<Void> player);
typedef TcPlayerRoundHasAchievementC = Int32 Function(
    Pointer<Void> player, Int32 achievement);
typedef TcPlayerRoundHasAchievementDart = int Function(
    Pointer<Void> player, int achievement);

// PlayerRound 结算查询
typedef TcPlayerRoundGetPositionResultC = Int32 Function(
    Pointer<Void> player, Int32 position, Pointer<THandResult> out);
typedef TcPlayerRoundGetPositionResultDart = int Function(
    Pointer<Void> player, int position, Pointer<THandResult> out);
typedef TcPlayerRoundGetNetScoreC = Int32 Function(Pointer<Void> player);
typedef TcPlayerRoundGetNetScoreDart = int Function(Pointer<Void> player);
typedef TcPlayerRoundIsFouledC = Int32 Function(Pointer<Void> player);
typedef TcPlayerRoundIsFouledDart = int Function(Pointer<Void> player);
typedef TcPlayerRoundIsHomerunC = Int32 Function(Pointer<Void> player);
typedef TcPlayerRoundIsHomerunDart = int Function(Pointer<Void> player);
typedef TcPlayerRoundGetShootCountC = Int32 Function(Pointer<Void> player);
typedef TcPlayerRoundGetShootCountDart = int Function(Pointer<Void> player);
typedef TcPlayerRoundGetShotCountC = Int32 Function(Pointer<Void> player);
typedef TcPlayerRoundGetShotCountDart = int Function(Pointer<Void> player);

// HandManager
typedef TcHandManagerCreateC = Pointer<Void> Function(Pointer<Int32> hand13);
typedef TcHandManagerCreateDart = Pointer<Void> Function(Pointer<Int32> hand13);
typedef TcHandManagerDestroyC = Void Function(Pointer<Void> mgr);
typedef TcHandManagerDestroyDart = void Function(Pointer<Void> mgr);
typedef TcHandManagerSelectCardC = Int32 Function(Pointer<Void> mgr, Int32 idx);
typedef TcHandManagerSelectCardDart = int Function(Pointer<Void> mgr, int idx);
typedef TcHandManagerDeselectCardC = Int32 Function(
    Pointer<Void> mgr, Int32 idx);
typedef TcHandManagerDeselectCardDart = int Function(
    Pointer<Void> mgr, int idx);
typedef TcHandManagerAddToPileC = Int32 Function(
    Pointer<Void> mgr, Int32 position, Int32 idx);
typedef TcHandManagerAddToPileDart = int Function(
    Pointer<Void> mgr, int position, int idx);
typedef TcHandManagerRemoveFromPileC = Int32 Function(
    Pointer<Void> mgr, Int32 position, Int32 idx);
typedef TcHandManagerRemoveFromPileDart = int Function(
    Pointer<Void> mgr, int position, int idx);
typedef TcHandManagerUndoC = Int32 Function(Pointer<Void> mgr);
typedef TcHandManagerUndoDart = int Function(Pointer<Void> mgr);
typedef TcHandManagerPileFullC = Int32 Function(
    Pointer<Void> mgr, Int32 position);
typedef TcHandManagerPileFullDart = int Function(
    Pointer<Void> mgr, int position);
typedef TcHandManagerSubmitC = Int32 Function(
    Pointer<Void> mgr, Pointer<TPattern> pat);
typedef TcHandManagerSubmitDart = int Function(
    Pointer<Void> mgr, Pointer<TPattern> pat);
typedef TcHandManagerGetCardStatusC = Int32 Function(
    Pointer<Void> mgr, Int32 idx);
typedef TcHandManagerGetCardStatusDart = int Function(
    Pointer<Void> mgr, int idx);
typedef TcHandManagerGetPileCountC = Int32 Function(
    Pointer<Void> mgr, Int32 position);
typedef TcHandManagerGetPileCountDart = int Function(
    Pointer<Void> mgr, int position);
typedef TcHandManagerGetPileCardC = Int32 Function(
    Pointer<Void> mgr, Int32 position, Int32 index);
typedef TcHandManagerGetPileCardDart = int Function(
    Pointer<Void> mgr, int position, int index);

// Round 管理
typedef TcRoundDealPlayersC = Int32 Function(
    Pointer<Pointer<Void>> players, Int32 playerCnt);
typedef TcRoundDealPlayersDart = int Function(
    Pointer<Pointer<Void>> players, int playerCnt);
typedef TcRoundClosePlayersC = Int32 Function(
    Pointer<Pointer<Void>> players, Int32 playerCnt);
typedef TcRoundClosePlayersDart = int Function(
    Pointer<Pointer<Void>> players, int playerCnt);

// Pattern 操作
typedef TcPatternInitC = Int32 Function(
    Pointer<Int32> hand13, Pointer<TPattern> out);
typedef TcPatternInitDart = int Function(
    Pointer<Int32> hand13, Pointer<TPattern> out);
typedef TcPatternSetPositionC = Int32 Function(
    Pointer<TPattern> p, Int32 position, Pointer<Int32> cards, Int32 count);
typedef TcPatternSetPositionDart = int Function(
    Pointer<TPattern> p, int position, Pointer<Int32> cards, int count);
typedef TcPatternGetPositionC = Int32 Function(
    Pointer<TPattern> p, Int32 position, Pointer<Int32> outBuf);
typedef TcPatternGetPositionDart = int Function(
    Pointer<TPattern> p, int position, Pointer<Int32> outBuf);

// 牌型名称中文化
typedef TcGetHandNameZhC = Pointer<Utf8> Function(Pointer<Utf8> enName);
typedef TcGetHandNameZhDart = Pointer<Utf8> Function(Pointer<Utf8> enName);

// ============================================================
//  ThirteenCardsFfi 封装
// ============================================================

class ThirteenCardsFfi {
  static DynamicLibrary? _lib;

  ThirteenCardsFfi._();

  /// 项目根目录 = 同时包含 `flutter/` 和 `build/` 的目录。
  /// 优先从 CARDS_ROOT 环境变量读取；否则根据当前工作目录推断。
  static String get _cardsRoot {
    if (Platform.environment['CARDS_ROOT'] case final root?) return root;
    final current = Directory.current;
    final dirName = current.path.split(Platform.pathSeparator).last;
    if (dirName == 'cards_flutter' || dirName == 'flutter') {
      return current.parent.path;
    }
    return current.path;
  }

  static DynamicLibrary get lib {
    if (_lib != null) return _lib!;
    final path = _libPath();
    _lib = DynamicLibrary.open(path);
    debugPrint('thirteen_ffi: loaded $path');
    return _lib!;
  }

  static String _libPath() {
    // Android：直接由 System.loadLibrary 从 jniLibs 加载
    if (Platform.isAndroid) return 'libthirteen_cards_cpp.so';
    if (Platform.environment['CARDS_THIRTEEN_DLL'] case final env?) {
      if (File(env).existsSync()) return env;
    }
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      for (final name in [
        'libthirteen_cards_cpp.dll',
        'runtime/libthirteen_cards_cpp.dll'
      ]) {
        final p = '$exeDir\\$name';
        if (File(p).existsSync()) return p;
      }
    } catch (_) {}
    final root = _cardsRoot;
    if (Platform.isWindows) {
      final fromRoot =
          '$root\\build\\libthirteen_cards_cpp.dll';
      if (File(fromRoot).existsSync()) return fromRoot;
    } else {
      final fromRoot =
          '$root/build/libthirteen_cards_cpp.so';
      if (File(fromRoot).existsSync()) return fromRoot;
    }
    if (Platform.isWindows) {
      if (Platform.environment['USERPROFILE'] case final home?) {
        final userPath =
            '$home\\cards\\Thirteen-Cards-main\\build\\libthirteen_cards_cpp.dll';
        if (File(userPath).existsSync()) return userPath;
      }
    } else {
      const fallback = '../build/libthirteen_cards_cpp.so';
      if (File(fallback).existsSync()) return fallback;
    }
    throw Exception(
      'Cannot find libthirteen_cards_cpp.(dll|so). '
      'Set CARDS_THIRTEEN_DLL or CARDS_ROOT environment variable.',
    );
  }

  // ================================================================
  //  牌型检测 (已有)
  // ================================================================

  static Map<String, dynamic> searchPattern(int position, List<int> cards) {
    if (cards.isEmpty)
      return {
        'position': position,
        'hand_name': 'Unknown',
        'rank_order': 0,
        'score': 0
      };
    final fn = lib.lookupFunction<TcSearchPatternC, TcSearchPatternDart>(
        'tc_search_pattern');
    final buf = calloc<Int32>(cards.length);
    for (var i = 0; i < cards.length; i++) buf[i] = cards[i];
    final result = fn(position, buf, cards.length);
    calloc.free(buf);
    final name =
        result.handName == nullptr ? 'Unknown' : result.handName.toDartString();
    return {
      'position': result.position,
      'hand_name': name,
      'rank_order': result.rankOrder,
      'score': result.score,
    };
  }

  // ================================================================
  //  DFS 枚举组合 (已有)
  // ================================================================

  static Map<String, dynamic> dfsEnumCombos(List<int> hand13, {int maxK = 64}) {
    final fn = lib.lookupFunction<TcDfsEnumCombosC, TcDfsEnumCombosDart>(
        'tc_dfs_enum_combos');
    final handBuf = calloc<Int32>(13);
    for (var i = 0; i < 13; i++) handBuf[i] = hand13[i];
    final out = calloc<TcDfsCandidateResult>(1);
    final rc = fn(handBuf, out, maxK);
    calloc.free(handBuf);
    if (rc != 0) {
      calloc.free(out);
      throw Exception('dfs_enum_combos returned $rc');
    }
    final isSpecial = out.ref.isSpecial != 0;
    final specialScore = out.ref.specialScore;
    final spName = isSpecial && out.ref.specialName != nullptr
        ? out.ref.specialName.toDartString()
        : '';
    final comboCount = out.ref.comboCount;
    final combos = <Map<String, dynamic>>[];
    for (var i = 0; i < comboCount && i < maxK; i++) {
      final c = out.ref.combos[i];
      final units = <Map<String, dynamic>>[];
      for (var u = 0; u < c.unitCount; u++) {
        final uData = c.units[u];
        final handName = uData.result.handName == nullptr
            ? ''
            : uData.result.handName.toDartString();
        units.add({
          'card_count': uData.cardCount,
          'cards': [for (var k = 0; k < uData.cardCount; k++) uData.cards[k]],
          'result': {
            'position': uData.result.position,
            'hand_name': handName,
            'rank_order': uData.result.rankOrder,
            'score': uData.result.score,
          },
        });
      }
      combos.add({
        'unit_count': c.unitCount,
        'units': units,
        'typed_score': c.typedScore,
        'loose_count': c.looseCount,
        'loose_cards': [for (var k = 0; k < c.looseCount; k++) c.looseCards[k]],
      });
    }
    calloc.free(out);
    return {
      'is_special': isSpecial,
      'special_score': specialScore,
      'special_name': spName,
      'combo_count': comboCount,
      'combos': combos,
    };
  }

  /// 原始 DFS 枚举 (不解析结构体，直接返回指针，供 AI 引擎传递到 onnx_helper)
  /// 调用方负责 free(handBuf) 和 free(out)
  static int dfsEnumCombosRaw(
      Pointer<Int32> handBuf, Pointer<TcDfsCandidateResult> out, int maxK) {
    final fn = lib.lookupFunction<TcDfsEnumCombosC, TcDfsEnumCombosDart>(
        'tc_dfs_enum_combos');
    return fn(handBuf, out, maxK);
  }

  // ================================================================
  //  牌比较 (已有)
  // ================================================================

  static int compareHead3(List<int> a, List<int> b) {
    final fn = lib.lookupFunction<TcCompareHead3C, TcCompareHead3Dart>(
        'tc_compare_head_3cards');
    return _compareCards(fn, a, b, 3);
  }

  static int compareFive(List<int> a, List<int> b) {
    final fn = lib.lookupFunction<TcCompareFiveC, TcCompareFiveDart>(
        'tc_compare_five_cards');
    return _compareCards(fn, a, b, 5);
  }

  static int _compareCards(int Function(Pointer<Int32>, Pointer<Int32>) fn,
      List<int> a, List<int> b, int n) {
    final bufA = calloc<Int32>(n);
    final bufB = calloc<Int32>(n);
    for (var i = 0; i < n; i++) {
      bufA[i] = a[i] % 52;
      bufB[i] = b[i] % 52;
    }
    final result = fn(bufA, bufB);
    calloc.free(bufA);
    calloc.free(bufB);
    return result;
  }

  static int compareHandResult(int roA, int roB) {
    final fn =
        lib.lookupFunction<TcCompareHandResultC, TcCompareHandResultDart>(
            'tc_compare_hand_result');
    return fn(roA, roB);
  }

  // ================================================================
  //  牌型名称中文化
  // ================================================================

  /// 查询牌型中文名，未找到时返回英文原名
  static String getHandNameZh(String enName) {
    final fn = lib.lookupFunction<TcGetHandNameZhC, TcGetHandNameZhDart>(
        'tc_get_hand_name_zh');
    final namePtr = enName.toNativeUtf8();
    final result = fn(namePtr);
    calloc.free(namePtr);
    return result == nullptr ? enName : result.toDartString();
  }

  // ================================================================
  //  PlayerRound 生命周期 (新增)
  // ================================================================

  /// 创建玩家对象
  static Pointer<Void> createPlayer(String name) {
    final fn =
        lib.lookupFunction<TcPlayerRoundCreateC, TcPlayerRoundCreateDart>(
            'tc_player_round_create');
    final namePtr = name.toNativeUtf8();
    final result = fn(namePtr);
    calloc.free(namePtr);
    return result;
  }

  /// 销毁玩家对象
  static void destroyPlayer(Pointer<Void> player) {
    final fn =
        lib.lookupFunction<TcPlayerRoundDestroyC, TcPlayerRoundDestroyDart>(
            'tc_player_round_destroy');
    fn(player);
  }

  /// 接收13张手牌（含特殊牌型自动检测）
  static int receiveHand(Pointer<Void> player, List<int> hand13) {
    assert(hand13.length == 13);
    final fn = lib.lookupFunction<TcPlayerRoundReceiveHandC,
        TcPlayerRoundReceiveHandDart>('tc_player_round_receive_hand');
    final buf = calloc<Int32>(13);
    for (var i = 0; i < 13; i++) buf[i] = hand13[i];
    final rc = fn(player, buf);
    calloc.free(buf);
    return rc;
  }

  /// 设置墩位（特殊牌型不可调用）
  static int setPosition(Pointer<Void> player, int position, List<int> cards) {
    assert(position >= 0 && position <= 2);
    assert(cards.length == (position == 0 ? 3 : 5));
    final fn = lib.lookupFunction<TcPlayerRoundSetPositionC,
        TcPlayerRoundSetPositionDart>('tc_player_round_set_position');
    final buf = calloc<Int32>(cards.length);
    for (var i = 0; i < cards.length; i++) buf[i] = cards[i];
    final rc = fn(player, position, buf, cards.length);
    calloc.free(buf);
    return rc;
  }

  /// 结算本局（返回本局原始得分）
  static int playerSettle(Pointer<Void> player) {
    final fn =
        lib.lookupFunction<TcPlayerRoundSettleC, TcPlayerRoundSettleDart>(
            'tc_player_round_settle');
    return fn(player);
  }

  /// 读取玩家原始13张手牌
  static List<int> getPlayerHand(Pointer<Void> player) {
    final fn =
        lib.lookupFunction<TcPlayerRoundGetHandC, TcPlayerRoundGetHandDart>(
            'tc_player_round_get_hand');
    final buf = calloc<Int32>(13);
    final rc = fn(player, buf);
    if (rc != 0) {
      calloc.free(buf);
      throw Exception('getPlayerHand returned $rc');
    }
    final result = [for (var i = 0; i < 13; i++) buf[i]];
    calloc.free(buf);
    return result;
  }

  /// 读取本局原始得分
  static int getRoundScore(Pointer<Void> player) {
    final fn = lib.lookupFunction<TcPlayerRoundGetRoundScoreC,
        TcPlayerRoundGetRoundScoreDart>('tc_player_round_get_round_score');
    return fn(player);
  }

  /// 读取累计总分
  static int getTotalScore(Pointer<Void> player) {
    final fn = lib.lookupFunction<TcPlayerRoundGetTotalScoreC,
        TcPlayerRoundGetTotalScoreDart>('tc_player_round_get_total_score');
    return fn(player);
  }

  /// 读取玩家名称
  static String getPlayerName(Pointer<Void> player) {
    final fn =
        lib.lookupFunction<TcPlayerRoundGetNameC, TcPlayerRoundGetNameDart>(
            'tc_player_round_get_name');
    final ptr = fn(player);
    return ptr == nullptr ? '' : ptr.toDartString();
  }

  /// 查询玩家是否拥有某成就
  static bool hasAchievement(Pointer<Void> player, int achievement) {
    final fn = lib.lookupFunction<TcPlayerRoundHasAchievementC,
        TcPlayerRoundHasAchievementDart>('tc_player_round_has_achievement');
    return fn(player, achievement) != 0;
  }

  // ================================================================
  //  PlayerRound 结算查询 (新增)
  // ================================================================

  /// 读取某墩的牌型结果（需在 closePlayers 之前调用）
  static Map<String, dynamic> getPositionResult(
      Pointer<Void> player, int position) {
    assert(position >= 0 && position <= 2);
    final fn = lib.lookupFunction<TcPlayerRoundGetPositionResultC,
            TcPlayerRoundGetPositionResultDart>(
        'tc_player_round_get_position_result');
    final out = calloc<THandResult>(1);
    final rc = fn(player, position, out);
    if (rc != 0) {
      calloc.free(out);
      return {
        'position': position,
        'hand_name': 'Unknown',
        'rank_order': 0,
        'score': 0
      };
    }
    final name = out.ref.handName == nullptr
        ? 'Unknown'
        : out.ref.handName.toDartString();
    final result = {
      'position': out.ref.position,
      'hand_name': name,
      'rank_order': out.ref.rankOrder,
      'score': out.ref.score,
    };
    calloc.free(out);
    return result;
  }

  /// 读取本局净得分（需在 closePlayers 之后调用）
  static int getNetScore(Pointer<Void> player) {
    final fn = lib.lookupFunction<TcPlayerRoundGetNetScoreC,
        TcPlayerRoundGetNetScoreDart>('tc_player_round_get_net_score');
    return fn(player);
  }

  /// 查询是否倒水（需在 closePlayers 之后调用）
  static bool isFouled(Pointer<Void> player) {
    final fn =
        lib.lookupFunction<TcPlayerRoundIsFouledC, TcPlayerRoundIsFouledDart>(
            'tc_player_round_is_fouled');
    return fn(player) != 0;
  }

  /// 查询是否全垒打（需在 closePlayers 之后调用）
  static bool isHomerun(Pointer<Void> player) {
    final fn =
        lib.lookupFunction<TcPlayerRoundIsHomerunC, TcPlayerRoundIsHomerunDart>(
            'tc_player_round_is_homerun');
    return fn(player) != 0;
  }

  /// 读取打枪次数（需在 closePlayers 之后调用）
  static int getShootCount(Pointer<Void> player) {
    final fn = lib.lookupFunction<TcPlayerRoundGetShootCountC,
        TcPlayerRoundGetShootCountDart>('tc_player_round_get_shoot_count');
    return fn(player);
  }

  /// 读取被打枪次数（需在 closePlayers 之后调用）
  static int getShotCount(Pointer<Void> player) {
    final fn = lib.lookupFunction<TcPlayerRoundGetShotCountC,
        TcPlayerRoundGetShotCountDart>('tc_player_round_get_shot_count');
    return fn(player);
  }

  // ================================================================
  //  HandManager 交互分墩 (新增)
  // ================================================================

  /// 创建分墩管理器
  static Pointer<Void> createManager(List<int> hand13) {
    assert(hand13.length == 13);
    final fn =
        lib.lookupFunction<TcHandManagerCreateC, TcHandManagerCreateDart>(
            'tc_hand_manager_create');
    final buf = calloc<Int32>(13);
    for (var i = 0; i < 13; i++) buf[i] = hand13[i];
    final mgr = fn(buf);
    calloc.free(buf);
    return mgr;
  }

  /// 销毁分墩管理器
  static void destroyManager(Pointer<Void> mgr) {
    final fn =
        lib.lookupFunction<TcHandManagerDestroyC, TcHandManagerDestroyDart>(
            'tc_hand_manager_destroy');
    fn(mgr);
  }

  /// 选牌 (UNSELECTED → SELECTED)
  static bool selectCard(Pointer<Void> mgr, int idx) {
    final fn = lib.lookupFunction<TcHandManagerSelectCardC,
        TcHandManagerSelectCardDart>('tc_hand_manager_select_card');
    return fn(mgr, idx) != 0;
  }

  /// 取消选牌 (SELECTED → UNSELECTED)
  static bool deselectCard(Pointer<Void> mgr, int idx) {
    final fn = lib.lookupFunction<TcHandManagerDeselectCardC,
        TcHandManagerDeselectCardDart>('tc_hand_manager_deselect_card');
    return fn(mgr, idx) != 0;
  }

  /// 放入墩位 (SELECTED → IN_PILE)
  static bool addToPile(Pointer<Void> mgr, int position, int idx) {
    final fn =
        lib.lookupFunction<TcHandManagerAddToPileC, TcHandManagerAddToPileDart>(
            'tc_hand_manager_add_to_pile');
    return fn(mgr, position, idx) != 0;
  }

  /// 从墩位移除 (IN_PILE → SELECTED)
  static bool removeFromPile(Pointer<Void> mgr, int position, int idx) {
    final fn = lib.lookupFunction<TcHandManagerRemoveFromPileC,
        TcHandManagerRemoveFromPileDart>('tc_hand_manager_remove_from_pile');
    return fn(mgr, position, idx) != 0;
  }

  /// 撤销上一步操作
  static bool undo(Pointer<Void> mgr) {
    final fn = lib.lookupFunction<TcHandManagerUndoC, TcHandManagerUndoDart>(
        'tc_hand_manager_undo');
    return fn(mgr) != 0;
  }

  /// 查询墩位是否已满
  static bool pileFull(Pointer<Void> mgr, int position) {
    final fn =
        lib.lookupFunction<TcHandManagerPileFullC, TcHandManagerPileFullDart>(
            'tc_hand_manager_pile_full');
    return fn(mgr, position) != 0;
  }

  /// 提交三墩到 Pattern
  static bool submitManager(Pointer<Void> mgr, Pointer<TPattern> pat) {
    final fn =
        lib.lookupFunction<TcHandManagerSubmitC, TcHandManagerSubmitDart>(
            'tc_hand_manager_submit');
    return fn(mgr, pat) != 0;
  }

  /// 查询单张牌状态: 0=UNSELECTED, 1=SELECTED, 2=IN_PILE
  static int getCardStatus(Pointer<Void> mgr, int idx) {
    final fn = lib.lookupFunction<TcHandManagerGetCardStatusC,
        TcHandManagerGetCardStatusDart>('tc_hand_manager_get_card_status');
    return fn(mgr, idx);
  }

  /// 查询墩中牌数
  static int getPileCount(Pointer<Void> mgr, int position) {
    final fn = lib.lookupFunction<TcHandManagerGetPileCountC,
        TcHandManagerGetPileCountDart>('tc_hand_manager_get_pile_count');
    return fn(mgr, position);
  }

  /// 读取墩中指定位置的牌
  static int getPileCard(Pointer<Void> mgr, int position, int index) {
    final fn = lib.lookupFunction<TcHandManagerGetPileCardC,
        TcHandManagerGetPileCardDart>('tc_hand_manager_get_pile_card');
    return fn(mgr, position, index);
  }

  // ================================================================
  //  Round 管理 (新增)
  // ================================================================

  /// DLL 侧洗牌+发牌：所有玩家每人13张
  static int dealPlayers(List<Pointer<Void>> players) {
    final fn = lib.lookupFunction<TcRoundDealPlayersC, TcRoundDealPlayersDart>(
        'tc_round_deal_players');
    final arr = calloc<Pointer<Void>>(players.length);
    for (var i = 0; i < players.length; i++) arr[i] = players[i];
    final rc = fn(arr, players.length);
    calloc.free(arr);
    return rc;
  }

  /// DLL 侧结算：两两比牌→打枪→全垒打→倒水买单→成就解锁
  static int closePlayers(List<Pointer<Void>> players) {
    final fn =
        lib.lookupFunction<TcRoundClosePlayersC, TcRoundClosePlayersDart>(
            'tc_round_close_players');
    final arr = calloc<Pointer<Void>>(players.length);
    for (var i = 0; i < players.length; i++) arr[i] = players[i];
    final rc = fn(arr, players.length);
    calloc.free(arr);
    return rc;
  }

  // ================================================================
  //  Pattern 操作 (新增)
  // ================================================================

  /// 初始化 Pattern
  static Pointer<TPattern> patternInit(List<int> hand13) {
    assert(hand13.length == 13);
    final fn = lib
        .lookupFunction<TcPatternInitC, TcPatternInitDart>('tc_pattern_init');
    final pat = calloc<TPattern>(1);
    final buf = calloc<Int32>(13);
    for (var i = 0; i < 13; i++) buf[i] = hand13[i];
    final rc = fn(buf, pat);
    calloc.free(buf);
    if (rc != 0) {
      calloc.free(pat);
      throw Exception('pattern_init returned $rc');
    }
    return pat;
  }

  /// 设置墩位
  static int patternSetPosition(
      Pointer<TPattern> pat, int position, List<int> cards) {
    final fn =
        lib.lookupFunction<TcPatternSetPositionC, TcPatternSetPositionDart>(
            'tc_pattern_set_position');
    final buf = calloc<Int32>(cards.length);
    for (var i = 0; i < cards.length; i++) buf[i] = cards[i];
    final rc = fn(pat, position, buf, cards.length);
    calloc.free(buf);
    return rc;
  }

  /// 读取墩位牌
  static List<int> patternGetPosition(Pointer<TPattern> pat, int position) {
    final fn =
        lib.lookupFunction<TcPatternGetPositionC, TcPatternGetPositionDart>(
            'tc_pattern_get_position');
    final len = position == 0 ? 3 : 5;
    final buf = calloc<Int32>(len);
    final rc = fn(pat, position, buf);
    if (rc != 0) {
      calloc.free(buf);
      return [];
    }
    final result = [for (var i = 0; i < len; i++) buf[i]];
    calloc.free(buf);
    return result;
  }

  // ================================================================
  //  PlayerStats (历史统计)
  // ================================================================

  /// 创建统计跟踪器
  static Pointer<Void> statsCreate(String name) {
    final fn = lib.lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Utf8>)>('tc_player_stats_create');
    final ptr = name.toNativeUtf8();
    final result = fn(ptr);
    calloc.free(ptr);
    return result;
  }

  /// 销毁统计跟踪器
  static void statsDestroy(Pointer<Void> stats) {
    final fn = lib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('tc_player_stats_destroy');
    fn(stats);
  }

  /// 记录一局分数
  static int statsAddRound(Pointer<Void> stats, int score) {
    final fn = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)>('tc_player_stats_add_round_score');
    return fn(stats, score);
  }

  /// 局数
  static int statsRoundCount(Pointer<Void> stats) {
    final fn = lib.lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('tc_player_stats_get_round_count');
    return fn(stats);
  }

  /// 第 idx 局的分数
  static int statsRoundScore(Pointer<Void> stats, int idx) {
    final fn = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)>('tc_player_stats_get_round_score');
    return fn(stats, idx);
  }

  /// 累计总分
  static int statsTotalScore(Pointer<Void> stats) {
    final fn = lib.lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('tc_player_stats_get_total_score');
    return fn(stats);
  }

  /// 成就位图
  static int statsAchievements(Pointer<Void> stats) {
    final fn = lib.lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('tc_player_stats_get_achievements');
    return fn(stats);
  }

  /// 设置成就位图
  static void statsSetAchievements(Pointer<Void> stats, int mask) {
    final fn = lib.lookupFunction<
        Void Function(Pointer<Void>, Uint32),
        void Function(Pointer<Void>, int)>('tc_player_stats_set_achievements');
    fn(stats, mask);
  }
}
