import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../backend/thirteen/thirteen_ffi.dart';
import '../../widgets/card_back.dart';

// ============================================================
//  常量
// ============================================================

const pileCmpKeys = ['head_cmp', 'middle_cmp', 'tail_cmp'];

// ============================================================
//  结算数据模型
// ============================================================

class ThirteenPlayerSettlement {
  ThirteenPlayerSettlement({
    required this.name,
    required this.head,
    required this.middle,
    required this.tail,
    required this.headResult,
    required this.middleResult,
    required this.tailResult,
    this.isSpecial = false,
    this.specialName = '',
    this.specialScore = 0,
  });

  final String name;
  final List<int> head;
  final List<int> middle;
  final List<int> tail;
  final Map<String, dynamic> headResult;
  final Map<String, dynamic> middleResult;
  final Map<String, dynamic> tailResult;
  final bool isSpecial;
  final String specialName;
  final int specialScore;
  bool fouled = false;
  bool homerun = false;
  int net = 0;
  int total = 0;
  int shootCount = 0;
  int achievements = 0;
  int headNet = 0;
  int middleNet = 0;
  int tailNet = 0;
}

class PairSettlement {
  const PairSettlement({
    required this.a,
    required this.b,
    required this.headCmp,
    required this.middleCmp,
    required this.tailCmp,
    required this.winner,
    required this.baseScore,
    required this.multiplier,
    required this.finalScore,
    required this.shootA,
    required this.shootB,
  });

  final int a;
  final int b;
  final int headCmp;
  final int middleCmp;
  final int tailCmp;
  final int winner;
  final int baseScore;
  final int multiplier;
  final int finalScore;
  final bool shootA;
  final bool shootB;
}

class TableSettlement {
  const TableSettlement({
    required this.players,
    required this.pairs,
  });

  final List<ThirteenPlayerSettlement> players;
  final List<PairSettlement> pairs;
}

// ============================================================
//  牌型名称中文化
// ============================================================

String handNameZh(String name) {
  if (name.isEmpty) return '-';
  try {
    final zh = ThirteenCardsFfi.getHandNameZh(name);
    if (zh.isNotEmpty) return zh;
  } catch (_) {}
  return name;
}

// ============================================================
//  结算栏底部状态文字
// ============================================================

String buildBottomStatus(TableSettlement s) {
  final me = s.players.isNotEmpty ? s.players.first : null;
  if (me == null) return '';
  final parts = <String>['本局：${me.net >= 0 ? '+' : ''}${me.net} 水'];
  for (final pair in s.pairs) {
    if (pair.shootA) {
      parts.add(
          '${s.players[pair.a].name} 打枪 ${s.players[pair.b].name} (+${pair.finalScore})');
    }
    if (pair.shootB) {
      parts.add(
          '${s.players[pair.b].name} 打枪 ${s.players[pair.a].name} (+${pair.finalScore})');
    }
  }
  for (final p in s.players) {
    if (p.homerun) parts.add('${p.name} 全垒打');
  }
  if (me.fouled) parts.add('倒水买单');
  return parts.join('，');
}

// ============================================================
//  玩家栏高度
// ============================================================

double stripHeight(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 760 ? 44.0 : 56.0;
}

// ============================================================
//  发牌动画 — 叠放牌背
// ============================================================

class DealCardStack extends StatelessWidget {
  const DealCardStack();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 80,
      height: 110,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 6, top: 4,
            child: CardBack(width: 72, height: 100, rotation: -6),
          ),
          Positioned(left: 3, top: 2,
            child: CardBack(width: 72, height: 100),
          ),
          Positioned(left: 0, top: 0,
            child: CardBack(width: 72, height: 100, rotation: 6),
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  3D 翻牌动画
// ============================================================

class FlipCard extends StatefulWidget {
  const FlipCard({
    required this.showFront,
    required this.frontChild,
    required this.backChild,
  });

  final bool showFront;
  final Widget frontChild;
  final Widget backChild;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  bool _hasFlipped = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    if (widget.showFront) {
      _hasFlipped = true;
      _ctrl.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(FlipCard old) {
    super.didUpdateWidget(old);
    if (widget.showFront && !_hasFlipped) {
      _hasFlipped = true;
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final value = _anim.value;
        final showFront = value >= 0.5;
        final angle = showFront ? (1 - value) * math.pi : value * math.pi;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: showFront ? widget.frontChild : widget.backChild,
        );
      },
    );
  }
}
