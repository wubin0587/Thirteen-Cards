import 'package:flutter/material.dart';

import '../../../models/card_model.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/card_back.dart';
import '../../../widgets/card_hand.dart';
import '../../../widgets/table_widgets.dart';
import '../thirteen_shared.dart';

// ============================================================
//  结算翻牌桌
// ============================================================

class SettlementTable extends StatelessWidget {
  const SettlementTable({
    super.key,
    required this.settlement,
    required this.revealStep,
  });

  final TableSettlement settlement;
  final int revealStep;

  @override
  Widget build(BuildContext context) {
    return FeltTable(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              const leftLabelW = 58.0;
              const gap = 8.0;
              final boardLeft = w > 900 ? 34.0 : 18.0;
              final boardTop = h > 360 ? 58.0 : 48.0;
              final visiblePlayers = settlement.players.length;
              final usableW =
                  w - boardLeft * 2 - leftLabelW - gap * visiblePlayers;
              final colW = (usableW / visiblePlayers).clamp(142.0, 260.0);
              final totalW = leftLabelW +
                  gap +
                  colW * settlement.players.length +
                  gap * (settlement.players.length - 1).clamp(0, 99);
              final contentW = totalW < w ? w : totalW + boardLeft * 2;
              final startX = totalW < w
                  ? ((w - totalW) / 2).clamp(8.0, boardLeft)
                  : boardLeft;
              final rowH = ((h - boardTop - 28) / 3).clamp(76.0, 124.0);
              final headerTop = boardTop - 32;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: contentW,
                  height: h,
                  child: Stack(
                    children: [
                      for (var i = 0; i < settlement.players.length; i++)
                        Positioned(
                          left: startX + leftLabelW + gap + i * (colW + gap),
                          top: headerTop,
                          width: colW,
                          height: 28,
                          child: _SettlementHeader(
                            player: settlement.players[i],
                            revealStep: revealStep,
                            totalPlayers: settlement.players.length,
                          ),
                        ),
                      for (var r = 0; r < 3; r++)
                        Positioned(
                          left: startX,
                          top: boardTop + r * (rowH + 8),
                          width: leftLabelW,
                          height: rowH,
                          child: _SettlementPileLabel(
                            label: const ['头墩', '中墩', '尾墩'][r],
                          ),
                        ),
                      for (var r = 0; r < 3; r++)
                        for (var i = 0; i < settlement.players.length; i++)
                          Positioned(
                            left: startX + leftLabelW + gap + i * (colW + gap),
                            top: boardTop + r * (rowH + 8),
                            width: colW,
                            height: rowH,
                            child: _SettlementPileCell(
                              player: settlement.players[i],
                              playerIndex: i,
                              pileIndex: r,
                              revealStep: revealStep,
                              totalPlayers: settlement.players.length,
                            ),
                          ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          top: 10,
          child: Center(
            child: Text(
              '摊牌结算',
              style: TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
//  玩家头栏
// ============================================================

class _SettlementHeader extends StatelessWidget {
  const _SettlementHeader({
    required this.player,
    required this.revealStep,
    required this.totalPlayers,
  });

  final ThirteenPlayerSettlement player;
  final int revealStep;
  final int totalPlayers;

  @override
  Widget build(BuildContext context) {
    final allDone = revealStep >= totalPlayers * 3;
    final netColor = player.net > 0
        ? AppColors.green
        : player.net < 0
            ? AppColors.danger
            : AppColors.dim;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 3,
          width: 84,
          height: 22,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              if (allDone && player.homerun) ...[
                const SizedBox(width: 4),
                const Text('🏠', style: TextStyle(fontSize: 16)),
              ],
            ],
          ),
        ),
        if (allDone)
          Positioned(
            right: 0,
            top: 2,
            width: 58,
            height: 24,
            child: Text(
              player.net >= 0 ? '+${player.net}' : '${player.net}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: netColor,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================
//  墩位标签（左列）
// ============================================================

class _SettlementPileLabel extends StatelessWidget {
  const _SettlementPileLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.lineStrong),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  单个翻牌单元格
// ============================================================

class _SettlementPileCell extends StatelessWidget {
  const _SettlementPileCell({
    required this.player,
    required this.playerIndex,
    required this.pileIndex,
    required this.revealStep,
    required this.totalPlayers,
  });

  final ThirteenPlayerSettlement player;
  final int playerIndex;
  final int pileIndex;
  final int revealStep;
  final int totalPlayers;

  bool get _revealed {
    final cellOrder = pileIndex * totalPlayers + playerIndex;
    return cellOrder <= revealStep;
  }

  bool get _rowDone {
    final rowLast = (pileIndex + 1) * totalPlayers - 1;
    return revealStep >= rowLast;
  }

  @override
  Widget build(BuildContext context) {
    final cards = switch (pileIndex) {
      0 => player.head,
      1 => player.middle,
      _ => player.tail,
    };
    final result = switch (pileIndex) {
      0 => player.headResult,
      1 => player.middleResult,
      _ => player.tailResult,
    };
    final rawName = result['hand_name']?.toString() ?? '';
    final pileNet = switch (pileIndex) { 0 => player.headNet, 1 => player.middleNet, _ => player.tailNet };
    final type = player.isSpecial ? player.specialName : handNameZh(rawName);
    final allDone = revealStep >= totalPlayers * 3;
    final border = allDone && player.homerun
        ? AppColors.gold
        : player.name == '我'
            ? AppColors.blue
            : AppColors.lineStrong;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: border,
          width: allDone && player.homerun ? 2.0 : player.name == '我' ? 1.6 : 1,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (_revealed) ...[
            Positioned(
              left: 8,
              top: 6,
              width: 78,
              height: 20,
              child: Text(
                type,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            if (_rowDone)
              Positioned(
                right: 8,
                top: 6,
                width: 40,
                height: 20,
                child: Text(
                  pileNet > 0 ? '+$pileNet' : '$pileNet',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: pileNet > 0
                        ? AppColors.green
                        : (pileNet < 0 ? AppColors.danger : AppColors.dim),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          Positioned(
            left: 8,
            right: 8,
            top: 26,
            bottom: 4,
            child: FlipCard(
              showFront: _revealed,
              backChild: StackedCardBacks(count: cards.length),
              frontChild: CardHand(
                cards: [for (final id in cards) PlayingCard.standard(id)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  墩位卡片（横屏布局）
// ============================================================
