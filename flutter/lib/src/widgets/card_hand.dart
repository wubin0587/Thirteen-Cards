import 'package:flutter/material.dart';

import '../models/card_model.dart';
import 'card_back.dart';
import 'card_tile.dart';

/// 横向排列手牌，宽度不足时自动重叠。
///
/// - 牌少（总宽 ≤ 父容器）→ 正常 6px 间距
/// - 牌多 → 自动压缩间距使牌重叠，每张牌至少露出 [minStep] px
/// - 压缩到 [minStep] 仍不够时允许横向滚动
class CardHand extends StatelessWidget {
  const CardHand({
    super.key,
    required this.cards,
    this.selectedIds = const {},
    this.disabledIds = const {},
    this.onCardTap,
    this.draggable = false,
    this.metrics,
  });

  final List<PlayingCard> cards;
  final Set<int> selectedIds;
  final Set<int> disabledIds;
  final ValueChanged<PlayingCard>? onCardTap;
  final bool draggable;
  final CardMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics ?? CardMetrics.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (cards.isEmpty) return SizedBox(height: m.height + 16);

        final step = computeCardStep(
          m.width, cards.length, constraints.maxWidth,
          normalGap: 6, minStep: 16,
        );

        final totalWidth = m.width + step * (cards.length - 1);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth,
            height: m.height + 16,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < cards.length; i++)
                  Positioned(
                    left: i * step,
                    bottom: 0,
                    child: _HandCard(
                      card: cards[i],
                      selected: selectedIds.contains(cards[i].id),
                      disabled: disabledIds.contains(cards[i].id),
                      onTap:
                          onCardTap == null ? null : () => onCardTap!(cards[i]),
                      metrics: m,
                      draggable: draggable,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HandCard extends StatelessWidget {
  const _HandCard({
    required this.card,
    required this.selected,
    required this.disabled,
    required this.metrics,
    required this.draggable,
    this.onTap,
  });

  final PlayingCard card;
  final bool selected;
  final bool disabled;
  final CardMetrics metrics;
  final bool draggable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = CardTile(
      card: card,
      selected: selected,
      disabled: disabled,
      onTap: disabled ? null : onTap,
      metrics: metrics,
    );
    if (!draggable) return tile;

    return Draggable<int>(
      data: card.id,
      feedback: Material(
        color: Colors.transparent,
        child: CardTile(
          card: card,
          selected: true,
          metrics: metrics,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.32, child: tile),
      child: tile,
    );
  }
}
