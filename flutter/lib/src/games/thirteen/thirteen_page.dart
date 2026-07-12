import 'dart:async';

import 'package:flutter/material.dart';

import '../../backend/achievement_store.dart';
import '../../backend/app_settings.dart';
import '../../backend/score_tracker.dart';
import '../../backend/stats_tracker.dart';
import '../../backend/thirteen/thirteen_ffi.dart';
import '../../models/card_model.dart';
import '../../i18n/strings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/card_hand.dart';
import '../../widgets/card_sounds.dart';
import '../../widgets/card_tile.dart';
import '../../widgets/stats_sheet.dart';
import '../../widgets/table_widgets.dart';
import '../../widgets/tts_engine.dart';
import 'ai/thirteen_style.dart';
import 'controller/thirteen_controller.dart';
import 'pile_position.dart';
import 'thirteen_shared.dart';
import 'widgets/thirteen_page_shell.dart';
import 'widgets/thirteen_table_widgets.dart';
import 'widgets/thirteen_settlement_widgets.dart';

class ThirteenPage extends StatefulWidget {
  const ThirteenPage({super.key, this.playerCount = 4});

  final int playerCount;

  @override
  State<ThirteenPage> createState() => _ThirteenPageState();
}

class _ThirteenPageState extends State<ThirteenPage> {
  late final ThirteenController _controller;
  ThirteenGameSession get _native => _controller.native;
  List<int> _hand = const [];
  List<List<int>> _hands = const [];
  TableSettlement? _settlement;
  String _status = '准备中';
  bool _busy = false;
  bool _showStyleOptions = false;
  int _revealStep = -1;
  bool _dealing = false;
  bool _skipReveal = false;
  List<int> _playerTotals = const [];
  List<AiProfile> _aiProfiles = const [];
  int _visibleCardCount = 0;
  bool _specialHandDetected = false;
  String _specialHandName = '';
  int _specialHandScore = 0;
  Timer? _dealTimer;

  @override
  void initState() {
    super.initState();
    _controller = ThirteenController(playerCount: widget.playerCount);
    _aiProfiles = AppSettings.pickForGame(widget.playerCount - 1);
    CardSounds.warmup();
    unawaited(TtsEngine.warmup());
    _newRound();
  }

  @override
  void dispose() {
    _dealTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 开始新一局：洗牌 → 发牌动画 → 准备摆墩
  Future<void> _newRound() async {
    _dealTimer?.cancel();
    setState(() {
      _busy = true;
      _status = '正在发牌';
      _settlement = null;
      _revealStep = -1;
      _skipReveal = false;
      _hands = const [];
      _hand = const [];
      _piles = { for (final p in PilePosition.values) p: <int>[] };
      _dealing = false;
      _visibleCardCount = 0;
      _specialHandDetected = false;
      _specialHandName = '';
      _specialHandScore = 0;
    });
    try {
      _controller.startRound();
      _hands = _controller.hands;
      _hand = _hands.first;
      if (!mounted) return;
      // 检测特殊牌型
      if (_native.arrangementStatus(0) == 3) {
        final sp = _native.getSpecialResult(0);
        setState(() {
          _specialHandDetected = true;
          _specialHandName = handNameZh(sp.name);
          _specialHandScore = sp.score;
          _busy = false;
          _status = '🎉 特殊牌型：${handNameZh(sp.name)}（${sp.score}水）';
        });
        return;
      }
      // 进入发牌动画阶段（非特殊牌型）
      setState(() {
        _dealing = true;
        _busy = false;
        _status = '发牌中…';
      });
      _startDealAnimation();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '发牌失败：$error';
      });
    }
  }

  /// 渐进发牌动画：每 ~70ms 揭示一张牌
  void _startDealAnimation() {
    const totalCards = 13;
    const interval = Duration(milliseconds: 70);
    _dealTimer = Timer.periodic(interval, (timer) {
      if (_visibleCardCount >= totalCards) {
        timer.cancel();
        _dealTimer = null;
        if (mounted) {
          setState(() {
            _dealing = false;
            _showStyleOptions = true;
            _status = '已发牌，可手动选择 AI 推荐';
          });
        }
        return;
      }
      if (mounted) {
        setState(() => _visibleCardCount++);
        unawaited(CardSounds.playDeal());
      }
    });
  }

  /// 推荐（计算 + 自动逐张摆墩）
  Future<void> _recommendAndApply(AiStyle style) async {
    if (_hand.length != 13) return;
    setState(() {
      _busy = true;
      _showStyleOptions = false;
      _status = '正在计算 ${_styleName(style)} 推荐';
    });
    try {
      final decision = await _controller.recommend(style);
      final data = decision.value;
      if (!mounted) return;

      // 推荐检测到特殊牌型 → 进入庆祝状态，不摆墩
      if (data['is_special'] == true) {
        final name = data['detected_special_name']?.toString() ?? '';
        final score =
            (data['detected_special_score'] as num?)?.toInt() ?? 0;
        setState(() {
          _specialHandDetected = true;
          _specialHandName = handNameZh(name);
          _specialHandScore = score;
          _status = '🎉 特殊牌型：${handNameZh(name)}（${score}水）';
        });
        return;
      }

      await _applyRecommendationAnimated(data);
      if (!mounted) return;

      setState(() {
        _showStyleOptions = true;
        _settlement = null;
        _status = decision.usedFallback
            ? '${_styleName(style)}摆墩完成（本地策略）'
            : '${_styleName(style)}摆墩完成';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '推荐失败：$error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 逐张填入动画
  Future<void> _applyRecommendationAnimated(Map<String, dynamic> data) async {
    final piles = PilePosition.values
        .map((p) => (pos: p, cards: _pileFromData(data, p)))
        .toList();

    setState(() {
      _piles = { for (final p in PilePosition.values) p: <int>[] };
    });
    await Future.delayed(const Duration(milliseconds: 30));

    for (final entry in piles) {
      for (final cardId in entry.cards) {
        if (!mounted) return;
        setState(() => _piles[entry.pos]!.add(cardId));
        unawaited(CardSounds.playPlace());
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  void _skipRevealAnimation() {
    _skipReveal = true;
    setState(() => _revealStep = widget.playerCount * 3);
  }

  /// 逐墩逐玩家翻牌 + 语音播报牌型（中文）
  Future<void> _startRevealAnimation() async {
    _skipReveal = false;
    if (_settlement == null) return;

    try {
      // ========================================================
      //  1. 先播报特殊牌型（不参与逐墩翻牌）
      // ========================================================
      final specialTts = <String>[];
      for (var i = 0; i < widget.playerCount; i++) {
        final p = _settlement!.players[i];
        if (p.isSpecial) {
          specialTts.add('${p.name}，${p.specialName}');
        }
      }
      if (specialTts.isNotEmpty) {
        await TtsEngine.speakMany(specialTts, gapMs: 0);
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // ========================================================
      //  2. 逐墩翻牌 — 每翻一人立即播报该人牌型（共 12 次）
      // ========================================================
      const pileDelay = Duration(milliseconds: 1000);
      for (var pile = 0; pile < 3 && !_skipReveal; pile++) {
        for (var player = 0;
            player < widget.playerCount && !_skipReveal; player++) {
          await Future.delayed(pileDelay);
          if (!mounted || _skipReveal) break;
          final step = pile * widget.playerCount + player;
          setState(() => _revealStep = step);

          // 特殊牌型玩家已在步骤 1 播报过，这里只翻牌不播报
          if (_settlement!.players[player].isSpecial) continue;

          final text = _cellRevealText(pile, player);
          if (text.isNotEmpty) {
            await TtsEngine.speak(text);
          }
        }
      }

      if (!mounted) return;
      setState(() => _revealStep = widget.playerCount * 3);
    } catch (_) {
      // 防止翻牌过程中任何异常阻止摘要播报
    }

    // ========================================================
    //  3. 逐条播报打枪/全垒打 + 交错音效
    // ========================================================
    // 重建 TTS 引擎（翻牌 12 次后旧实例可能内部状态异常）
    await TtsEngine.recreate();

    for (final pair in _settlement!.pairs) {
      if (pair.shootA) {
        await TtsEngine.speakAndWait(
            '${_settlement!.players[pair.a].name}打枪${_settlement!.players[pair.b].name}');
        CardSounds.playShootEach();
      }
      if (pair.shootB) {
        await TtsEngine.speakAndWait(
            '${_settlement!.players[pair.b].name}打枪${_settlement!.players[pair.a].name}');
        CardSounds.playShootEach();
      }
    }
    for (final p in _settlement!.players) {
      if (p.homerun) {
        await TtsEngine.speakAndWait('${p.name}全垒打');
        CardSounds.playHomerunEach();
      }
    }
  }

  String _cellRevealText(int pileIdx, int pIdx) {
    if (_settlement == null) return '';
    if (pIdx >= _settlement!.players.length) return '';
    final p = _settlement!.players[pIdx];
    final result = switch (pileIdx) {
      0 => p.headResult,
      1 => p.middleResult,
      _ => p.tailResult,
    };
    final zh = handNameZh(result['hand_name']?.toString() ?? '');
    if (zh.isEmpty || zh == '-') return '';
    return zh;
  }

  String _styleName(AiStyle style) {
    final s = AppStrings.of();
    return switch (style) {
      AiStyle.conservative => s.tcConservative,
      AiStyle.balanced => s.tcDefault,
      AiStyle.aggressive => s.tcAggressive,
    };
  }

  List<int> _pileFromData(Map<String, dynamic> data, PilePosition pos) {
    final pile = data[pos.key] as Map<String, dynamic>?;
    final cards = pile?['cards'] as List<dynamic>?;
    return cards?.cast<int>() ?? const [];
  }

  /// 原生引擎检测墩位牌型 + 得分。
  ({String name, String score}) _pileInfo(PilePosition pos) {
    final cards = _piles[pos]!;
    if (cards.isEmpty) return (name: '-', score: '');
    final result = ThirteenCardsFfi.searchPattern(pos.positionIndex, cards);
    final rawScore = (result['score'] as num?)?.toInt() ?? 0;
    return (
      name: handNameZh(result['hand_name']?.toString() ?? ''),
      score: rawScore < 0 ? '$rawScore' : '+$rawScore',
    );
  }

  Map<PilePosition, List<int>> _piles = {
    PilePosition.head: <int>[],
    PilePosition.middle: <int>[],
    PilePosition.tail: <int>[],
  };

  /// 点击手牌 → 按头墩→中墩→尾墩顺序自动放入
  void _toggleCard(PlayingCard card) {
    if (_busy) return;
    final cardId = card.id;
    // 如果已在某个牌墩中，从所有牌墩移除
    if (_piles.values.any((list) => list.contains(cardId))) {
      setState(() {
        for (final list in _piles.values) list.remove(cardId);
        _settlement = null;
      });
      unawaited(CardSounds.playRemove());
      return;
    }
    // 找第一个有空位的牌墩放入
    final target = PilePosition.values.firstWhere(
      (p) => _piles[p]!.length < p.cardCount,
      orElse: () => PilePosition.tail,
    );
    if (_piles[target]!.length >= target.cardCount) return;
    setState(() {
      _settlement = null;
      _piles[target]!.add(cardId);
      _status = '已放入${target.label}';
    });
    unawaited(CardSounds.playPlace());
  }

  void _removeFromPile(String pile, int cardId) {
    if (_busy) return;
    final pos = PilePosition.fromKey(pile);
    setState(() {
      _piles[pos]!.remove(cardId);
      _settlement = null;
    });
    unawaited(CardSounds.playRemove());
  }

  void _returnToHand(int cardId) {
    if (_busy) return;
    setState(() {
      for (final list in _piles.values) list.remove(cardId);
      _settlement = null;
    });
    unawaited(CardSounds.playRemove());
  }

  void _onDropToPile(String pile, int cardId) {
    if (_busy || !_hand.contains(cardId)) return;
    final pos = PilePosition.fromKey(pile);
    final target = _piles[pos]!;
    if (target.length >= pos.cardCount) {
      setState(() => _status = '${pos.label}已满');
      return;
    }
    setState(() {
      _settlement = null;
      for (final list in _piles.values) list.remove(cardId);
      target.add(cardId);
      _status = '已放入${pos.label}';
    });
    unawaited(CardSounds.playPlace());
  }

  String _aiName(int aiIndex) {
    if (aiIndex < 0 || aiIndex >= _aiProfiles.length) return 'AI ${aiIndex + 1}';
    return _aiProfiles[aiIndex].name;
  }

  /// 按 DLL 的 card_rank 排序（rank 0=2 最小，rank 12=A 最大），
  /// 同点数按花色 D<C<H<S 排列。
  List<PlayingCard> _sortedHandCards(List<PlayingCard> cards) {
    final sorted = [...cards];
    sorted.sort((a, b) {
      final byRank = b.rank.compareTo(a.rank);
      return byRank != 0 ? byRank : a.suit.code.compareTo(b.suit.code);
    });
    return sorted;
  }

  void _undoLastAction() {
    if (_busy) return;
    unawaited(CardSounds.playRemove());
    setState(() {
      _settlement = null;
      for (final list in _piles.values) list.clear();
    });
  }

  TableSettlement _loadNativeSettlement() {
    final players = <ThirteenPlayerSettlement>[];
    for (var i = 0; i < widget.playerCount; i++) {
      final data = _native.playerSettlement(i);
      final special = data['special_result'] as Map<String, dynamic>;
      final player = ThirteenPlayerSettlement(
        name: i == 0 ? '我' : _aiName(i - 1),
        head: (data['head'] as List<dynamic>).cast<int>(),
        middle: (data['middle'] as List<dynamic>).cast<int>(),
        tail: (data['tail'] as List<dynamic>).cast<int>(),
        headResult: Map<String, dynamic>.from(data['head_result'] as Map),
        middleResult: Map<String, dynamic>.from(data['middle_result'] as Map),
        tailResult: Map<String, dynamic>.from(data['tail_result'] as Map),
        isSpecial: data['is_special'] == true,
        specialName: handNameZh(special['hand_name']?.toString() ?? ''),
        specialScore: (special['score'] as num?)?.toInt() ?? 0,
      )
        ..fouled = data['fouled'] == true
        ..homerun = data['homerun'] == true
        ..net = (data['net'] as num).toInt()
        ..total = (data['total'] as num).toInt()
        ..achievements = (data['achievements'] as int?) ?? 0;
      players.add(player);
    }

    // 读取 pairwise 结果，计算每墩净胜分 + 打枪数
    final pairData = _native.pairSettlements();
    for (final pd in pairData) {
      if (pd['shoot_a'] == true) players[pd['a'] as int].shootCount++;
      if (pd['shoot_b'] == true) players[pd['b'] as int].shootCount++;
    }
    final pileScore = [
      (int i) => (players[i].headResult['score'] as num?)?.toInt() ?? 0,
      (int i) => (players[i].middleResult['score'] as num?)?.toInt() ?? 0,
      (int i) => (players[i].tailResult['score'] as num?)?.toInt() ?? 0,
    ];
    for (final pd in pairData) {
      final a = pd['a'] as int;
      final b = pd['b'] as int;
      final mult = pd['multiplier'] as int;
      for (var pos = 0; pos < 3; pos++) {
        final cmp = pd[pileCmpKeys[pos]] as int;
        if (cmp == 0) continue;
        final winIdx = cmp > 0 ? a : b;
        final loseIdx = cmp > 0 ? b : a;
        final gain = pileScore[pos](winIdx) * mult;
        if (pos == 0) { players[winIdx].headNet += gain; players[loseIdx].headNet -= gain; }
        if (pos == 1) { players[winIdx].middleNet += gain; players[loseIdx].middleNet -= gain; }
        if (pos == 2) { players[winIdx].tailNet += gain; players[loseIdx].tailNet -= gain; }
      }
    }

    final pairs = [
      for (final data in pairData)
        PairSettlement(
          a: data['a'] as int,
          b: data['b'] as int,
          headCmp: data['head_cmp'] as int,
          middleCmp: data['middle_cmp'] as int,
          tailCmp: data['tail_cmp'] as int,
          winner: data['winner'] as int,
          baseScore: data['base_score'] as int,
          multiplier: data['multiplier'] as int,
          finalScore: data['final_score'] as int,
          shootA: data['shoot_a'] == true,
          shootB: data['shoot_b'] == true,
        ),
    ];
    return TableSettlement(players: players, pairs: pairs);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final h = _piles[PilePosition.head]!.length,
        m = _piles[PilePosition.middle]!.length,
        t = _piles[PilePosition.tail]!.length;
    if (h != 3 || m != 5 || t != 5) {
      setState(() => _status = '头墩3张/中墩5张/尾墩5张，当前$h/$m/$t');
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在按 DLL 规则结算整桌';
    });
    try {
      final settlement = await _submitToNative();
      if (settlement == null || !mounted) return;
      _onSettled(settlement);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '提交失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 特殊牌型 → 确认结算。
  Future<void> _specialHandSubmit() async {
    setState(() {
      _busy = true;
      _status = '正在结算特殊牌型…';
    });
    try {
      final settlement = await _submitToNative();
      if (settlement == null || !mounted) return;
      _onSettled(settlement);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '结算失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 提交到 DLL：apply → 倒水确认 → submit → AI 摆墩 → settle → 加载结算。
  /// 用户取消倒水时返回 null。
  Future<TableSettlement?> _submitToNative() async {
    // 特殊牌型：跳过 apply+submit，直接走 AI 摆墩 → settle
    if (_native.isSpecial(0)) {
      for (var i = 1; i < widget.playerCount; i++) {
        final aggression = i - 1 < _aiProfiles.length
            ? _aiProfiles[i - 1].aggression
            : 0.0;
        final strategy = aggression < -0.3
            ? 1
            : aggression > 0.3
                ? 2
                : 0;
        _native.autoArrange(i, strategy);
      }
      _native.settle();
      return _loadNativeSettlement();
    }
    _native.apply(0, {
      'is_special': false,
      for (final p in PilePosition.values) p.key: _piles[p]!,
    });
    bool allowFouled = false;
    if (_native.arrangementStatus(0) == 2) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('倒水警告'),
          content: const Text('DLL判定当前摆牌倒水，是否继续提交？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('继续')),
          ],
        ),
      );
      if (confirm != true) return null;
      allowFouled = true;
    }
    _native.submit(0, allowFouled: allowFouled);
    for (var i = 1; i < widget.playerCount; i++) {
      final aggression = i - 1 < _aiProfiles.length
          ? _aiProfiles[i - 1].aggression
          : 0.0;
      final strategy = aggression < -0.3
          ? 1
          : aggression > 0.3
              ? 2
              : 0;
      _native.autoArrange(i, strategy);
    }
    _native.settle();
    return _loadNativeSettlement();
  }

  /// 结算后处理：更新 UI → 记录统计 → 成就检测（shootCount 只算一次）。
  void _onSettled(TableSettlement settlement) {
    final players = settlement.players;
    final me = settlement.players.first;
    final shootCount =
        settlement.pairs.where((p) => p.shootA || p.shootB).length;
    final ach = me.achievements;

    if (!mounted) return;
    _playerTotals = players.map((p) => p.total).toList();
    setState(() {
      _showStyleOptions = false;
      _revealStep = -1;
      _settlement = settlement;
      final allHomeruns = settlement.players.where((p) => p.homerun).toList();
      final tags = [
        if (me.fouled) '倒水买单',
        if (allHomeruns.isNotEmpty)
          allHomeruns.map((p) => '${p.name}全垒打').join('/'),
        if (shootCount > 0) '打枪$shootCount次',
      ].join(' / ');
      _status = '本局：${me.net >= 0 ? '+' : ''}${me.net} 水'
          '${tags.isEmpty ? '' : '，$tags'}';
    });
    unawaited(_startRevealAnimation());

    StatsTracker.instance.recordRound(
      me.net,
      achievementsMask: ach,
      homerun: me.homerun,
      fouled: me.fouled,
      shootCount: shootCount,
    );

    unawaited(ThirteenScoreStore.instance.record(
      ThirteenRoundRecord(
        time: DateTime.now(),
        playerCount: widget.playerCount,
        mySeat: 0,
        nets: players.map((p) => p.net).toList(),
        shootCount: shootCount,
        fouled: me.fouled,
        homerun: me.homerun,
        specialName: me.isSpecial ? me.specialName : '',
        headHand: me.isSpecial ? null : _pileInfo(PilePosition.head).name,
        middleHand: me.isSpecial ? null : _pileInfo(PilePosition.middle).name,
        tailHand: me.isSpecial ? null : _pileInfo(PilePosition.tail).name,
        headScore: me.isSpecial ? null : (me.headResult['score'] as num?)?.toInt(),
        middleScore: me.isSpecial ? null : (me.middleResult['score'] as num?)?.toInt(),
        tailScore: me.isSpecial ? null : (me.tailResult['score'] as num?)?.toInt(),
        headCards: me.isSpecial ? null : _piles[PilePosition.head],
        middleCards: me.isSpecial ? null : _piles[PilePosition.middle],
        tailCards: me.isSpecial ? null : _piles[PilePosition.tail],
      ),
    ));

    unawaited(_checkAchievements(
      myNet: me.net,
      isWin: me.net > 0,
      homerun: me.homerun,
      fouled: me.fouled,
      shootCount: shootCount,
      hasSpecialHand: me.isSpecial,
      dllAchievementsMask: ach,
    ));
  }

  /// 每局结束后检测成就解锁。
  Future<void> _checkAchievements({
    required int myNet,
    required bool isWin,
    required bool homerun,
    required bool fouled,
    required int shootCount,
    required bool hasSpecialHand,
    int dllAchievementsMask = 0,
  }) async {
    try {
      final store = ThirteenScoreStore.instance;
      final wins = store.cachedWins;
      final totalNet = store.cachedTotalNet;
      final totalHomeruns = store.cachedHomeruns;
      final totalShoots = store.cachedShoots;
      // 连胜直接从缓存顺序扫描（仅扫描连续胜局，不读全部 200 条）
      final streak = store.currentStreak;

      AchievementStore.instance.updateSnapshot(
        wins: wins,
        totalNet: totalNet,
        homeruns: totalHomeruns,
        shoots: totalShoots,
        streak: streak,
        specialHandCount: _popCount(dllAchievementsMask),
      );

      final newly = await AchievementStore.instance.checkAfterRound(
        myNet: myNet,
        isWin: isWin,
        homerun: homerun,
        fouled: fouled,
        shootCount: shootCount,
        hasSpecialHand: hasSpecialHand,
        dllAchievementsMask: dllAchievementsMask,
        totalWins: wins,
        totalNet: totalNet,
        totalHomeruns: totalHomeruns,
        totalShoots: totalShoots,
        currentStreak: streak,
        specialHandCount: _popCount(dllAchievementsMask),
      );

      if (newly.isNotEmpty && mounted) {
        final names = newly
            .map((id) => kAllAchievements[id]?.name ?? id)
            .join('、');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🏅 解锁成就：$names'),
            backgroundColor: const Color(0xFF1A3A5C),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  /// 浮动风格切换标签
  Widget _buildStyleChips() {
    final s = AppStrings.of();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StyleChip(
          label: s.tcConservative,
          onTap: () => _recommendAndApply(AiStyle.conservative),
        ),
        const SizedBox(width: 6),
        StyleChip(
          label: s.tcDefault,
          recommended: true,
          onTap: () => _recommendAndApply(AiStyle.balanced),
        ),
        const SizedBox(width: 6),
        StyleChip(
          label: s.tcAggressive,
          onTap: () => _recommendAndApply(AiStyle.aggressive),
        ),
      ],
    );
  }

  /// 发牌阶段桌面：牌堆 + 玩家栏
  Widget _buildDealingTable() {
    final text = AppTextTokens.of(context);
    return FeltTable(
      children: [
        Positioned(
          left: 76, right: 76, top: 8,
          height: stripHeight(context),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _DealingPlayerChip(label: '我', isMe: true),
                for (final name in _aiProfiles.map((p) => p.name)) ...[
                  const SizedBox(width: 10),
                  _DealingPlayerChip(label: name),
                ],
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DealCardStack(),
                const SizedBox(height: 20),
                Text('发牌中…',
                    style: TextStyle(
                        color: AppColors.gold, fontSize: text.lg, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('请等待发牌完成',
                    style: TextStyle(color: AppColors.dim, fontSize: text.sm)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 特殊牌型展示：13 张牌摊开 + 名称 + 结算按钮。
  Widget _buildSpecialHandDisplay() {
    final text = AppTextTokens.of(context);
    final handCards =
        _sortedHandCards(_hand.map(PlayingCard.standard).toList());
    return FeltTable(
      children: [
        Positioned.fill(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🎉', style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text('特殊牌型',
                    style: TextStyle(
                        color: AppColors.gold,
                        fontSize: text.lg,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(_specialHandName,
                    style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 28,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('${_specialHandScore} 水',
                    style: TextStyle(
                        color: AppColors.green,
                        fontSize: text.lg,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 24),
                SizedBox(
                  height: CardMetrics.of(context).height + 16,
                  child: CardHand(
                    cards: handCards,
                    metrics: CardMetrics.of(context),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _specialHandSubmit,
                  icon: const Icon(Icons.check_circle_rounded, size: 28),
                  label: const Text('确认结算',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.ink,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final handCards =
        _sortedHandCards(_hand.map(PlayingCard.standard).toList());
    final placed = {
      for (final p in PilePosition.values) ..._piles[p]!,
    };

    // 手牌：发牌中只显示已揭示的，否则显示全部
    final unplacedCards =
        handCards.where((c) => !placed.contains(c.id)).toList();
    final displayCards = _dealing
        ? unplacedCards.take(_visibleCardCount).toList()
        : unplacedCards;

    Widget tableContent;
    if (_settlement != null) {
      final revealing = _revealStep >= 0 &&
          _revealStep < widget.playerCount * 3 - 1 &&
          !_skipReveal;
      tableContent = Stack(
        children: [
          SettlementTable(
            settlement: _settlement!,
            revealStep: _revealStep,
          ),
          if (revealing)
            Positioned(
              right: 10,
              top: 10,
              child: TextButton.icon(
                onPressed: _skipRevealAnimation,
                icon: const Icon(Icons.skip_next, color: AppColors.dim),
                label: const Text('跳过',
                    style: TextStyle(color: AppColors.dim)),
              ),
            ),
        ],
      );
    } else if (_specialHandDetected) {
      tableContent = _buildSpecialHandDisplay();
    } else if (_dealing) {
      tableContent = _buildDealingTable();
    } else {
      final headInfo = _pileInfo(PilePosition.head);
      final midInfo = _pileInfo(PilePosition.middle);
      final tailInfo = _pileInfo(PilePosition.tail);
      tableContent = ThirteenTable(
        head: _piles[PilePosition.head]!,
        middle: _piles[PilePosition.middle]!,
        tail: _piles[PilePosition.tail]!,
        headName: headInfo.name,
        middleName: midInfo.name,
        tailName: tailInfo.name,
        headScore: headInfo.score,
        middleScore: midInfo.score,
        tailScore: tailInfo.score,
        playerCount: widget.playerCount,
        totals: _playerTotals,
        aiNames: _aiProfiles.map((p) => p.name).toList(),
        onRemove: _removeFromPile,
        onDrop: _onDropToPile,
      );
    }

    return Scaffold(
      body: TableStage(
        sideBoard: const SizedBox.shrink(),
        phase: const SizedBox.shrink(),
        table: tableContent,
        styleChips: _showStyleOptions ? _buildStyleChips() : null,
        actionDock: ThirteenActionBar(
          busy: _busy,
          settled: _settlement != null,
          pilesFull: PilePosition.values
              .every((p) => _piles[p]!.length >= p.cardCount),
          onRecommend: () => _recommendAndApply(AiStyle.balanced),
          onUndo: _undoLastAction,
          onSubmit: _submit,
          onNewRound: _newRound,
        ),
        showActions: !_busy && !_specialHandDetected,
        toast: _settlement != null ? '' : _status,
        settlementStatus: _settlement != null &&
                _revealStep >= widget.playerCount * 3
            ? buildBottomStatus(_settlement!)
            : null,
        onStats: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => const StatsSheet(),
        ),
        handTitle: _dealing ? '发牌中…' : '我的手牌',
        handSubtitle: '',
        hand: DragTarget<int>(
          onAcceptWithDetails: (details) => _returnToHand(details.data),
          builder: (context, candidates, rejected) {
            return Column(
              children: [
                if (_dealing)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '$_visibleCardCount / 13',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: AppTextTokens.of(context).md,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: DecoratedBox(
                    decoration: candidates.isEmpty
                        ? const BoxDecoration()
                        : BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.gold, width: 2),
                          ),
                    child: CardHand(
                      cards: displayCards,
                      onCardTap: _dealing ? null : _toggleCard,
                      draggable: !_dealing,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DealingPlayerChip extends StatelessWidget {
  const _DealingPlayerChip({required this.label, this.isMe = false});

  final String label;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Container(
      height: compact ? 34 : 44,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
      decoration: BoxDecoration(
        color: isMe ? AppColors.blue.withValues(alpha: 0.15) : AppColors.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: isMe ? AppColors.blue : AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.text, fontSize: compact ? 12 : 14, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

/// 计算 32 位整数的置位数（popcount），兼容 Flutter Windows dart2native。
int _popCount(int x) {
  x = x & 0xFFFFFFFF;
  x = x - ((x >> 1) & 0x55555555);
  x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
  x = (x + (x >> 4)) & 0x0F0F0F0F;
  x = x + (x >> 8);
  x = x + (x >> 16);
  return x & 0x3F;
}
