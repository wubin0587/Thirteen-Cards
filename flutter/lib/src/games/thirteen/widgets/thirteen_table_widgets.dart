import 'package:flutter/material.dart';

import '../../../models/card_model.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/card_hand.dart';
import '../../../widgets/table_widgets.dart';
import '../pile_position.dart';
import '../thirteen_shared.dart';

// ============================================================
//  牌桌 — 三墩摆牌区
// ============================================================

class ThirteenTable extends StatelessWidget {
  const ThirteenTable({
    super.key,
    required this.head,
    required this.middle,
    required this.tail,
    required this.headName,
    required this.middleName,
    required this.tailName,
    required this.headScore,
    required this.middleScore,
    required this.tailScore,
    required this.playerCount,
    required this.totals,
    required this.aiNames,
    required this.onRemove,
    this.onDrop,
  });

  final List<int> head;
  final List<int> middle;
  final List<int> tail;
  final String headName;
  final String middleName;
  final String tailName;
  final String headScore;
  final String middleScore;
  final String tailScore;
  final int playerCount;
  final List<int> totals;
  final List<String> aiNames;
  final void Function(String pile, int cardId) onRemove;
  final void Function(String pile, int cardId)? onDrop;

  @override
  Widget build(BuildContext context) {
    final boardTop = 8.0 + stripHeight(context) + 12;
    return FeltTable(
      children: [
        Positioned(
          left: 76,
          right: 76,
          top: 8,
          height: stripHeight(context),
          child: _PlayerScoreStrip(
            playerCount: playerCount,
            totals: totals,
            aiNames: aiNames,
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(28, boardTop, 28, 28),
            child: _PileBoard(
              head: head,
              middle: middle,
              tail: tail,
              headName: headName,
              middleName: middleName,
              tailName: tailName,
              headScore: headScore,
              middleScore: middleScore,
              tailScore: tailScore,
              onRemove: onRemove,
              onDrop: onDrop,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
//  三墩面板
// ============================================================

class _PileBoard extends StatelessWidget {
  const _PileBoard({
    required this.head,
    required this.middle,
    required this.tail,
    required this.headName,
    required this.middleName,
    required this.tailName,
    required this.headScore,
    required this.middleScore,
    required this.tailScore,
    required this.onRemove,
    this.onDrop,
  });

  final List<int> head;
  final List<int> middle;
  final List<int> tail;
  final String headName;
  final String middleName;
  final String tailName;
  final String headScore;
  final String middleScore;
  final String tailScore;
  final void Function(String pile, int cardId) onRemove;
  final void Function(String pile, int cardId)? onDrop;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;

    Widget _wrapPile(Widget child, String pileName) {
      if (onDrop == null) return child;
      return DragTarget<int>(
        onAcceptWithDetails: (details) => onDrop!(pileName, details.data),
        builder: (context, candidates, rejected) {
          final hovering = candidates.isNotEmpty;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: hovering
                  ? Border.all(color: AppColors.gold, width: 2)
                  : null,
            ),
            child: child,
          );
        },
      );
    }

    final heads = [head, middle, tail];
    final titles = ['头墩', '中墩', '尾墩'];
    final names = [headName, middleName, tailName];
    final scores = [headScore, middleScore, tailScore];
    final flexes = [7, 10, 10];
    final positions = PilePosition.values;

    if (landscape) {
      return Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              flex: flexes[i],
              child: _wrapPile(
                _PileSlot(
                  title: titles[i],
                  subtitle: names[i],
                  score: scores[i],
                  cards: heads[i],
                  onCardTap: (card) => onRemove(positions[i].key, card.id),
                ),
                positions[i].key,
              ),
            ),
        ],
      );
    }

    return Column(
      children: List.generate(3, (i) {
        final f = i == 0 ? 8 : 10;
        return Expanded(
          flex: f,
          child: Padding(
            padding: i > 0 ? const EdgeInsets.only(top: 8) : EdgeInsets.zero,
            child: _wrapPile(
              _PileRow(
                title: titles[i],
                subtitle: names[i],
                score: scores[i],
                cards: heads[i],
                onCardTap: (card) => onRemove(positions[i].key, card.id),
              ),
              positions[i].key,
            ),
          ),
        );
      }),
    );
  }
}

// ============================================================
//  单墩行（竖屏）
// ============================================================

class _PileRow extends StatelessWidget {
  const _PileRow({
    required this.title,
    required this.subtitle,
    required this.score,
    required this.cards,
    this.onCardTap,
  });

  final String title;
  final String subtitle;
  final String score;
  final List<int> cards;
  final ValueChanged<PlayingCard>? onCardTap;

  @override
  Widget build(BuildContext context) {
    final text = AppTextTokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.lineStrong, width: 1.5),
        ),
        child: Row(
          children: [
            SizedBox(
              width: compact ? 110 : 140,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: text.lg + 4,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.muted, fontSize: text.md),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CardHand(
                cards: [for (final id in cards) PlayingCard.standard(id)],
                onCardTap: onCardTap,
                draggable: true,
              ),
            ),
            SizedBox(
              width: compact ? 54 : 78,
              child: Text(
                score,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: score.startsWith('-')
                      ? AppColors.danger
                      : (score == '+0' || score == '0'
                          ? AppColors.dim
                          : AppColors.green),
                  fontSize: text.score,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
    );
  }
}

// ============================================================
//  玩家得分栏
// ============================================================

class _PlayerScoreStrip extends StatelessWidget {
  const _PlayerScoreStrip({
    required this.playerCount,
    required this.totals,
    required this.aiNames,
  });

  final int playerCount;
  final List<int> totals;
  final List<String> aiNames;

  @override
  Widget build(BuildContext context) {
    if (playerCount <= 0) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < playerCount; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            _PlayerScoreChip(
              label: i == 0
                  ? '我'
                  : (i - 1 < aiNames.length ? aiNames[i - 1] : 'AI $i'),
              total: i < totals.length ? totals[i] : 0,
              isMe: i == 0,
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerScoreChip extends StatelessWidget {
  const _PlayerScoreChip({
    required this.label,
    required this.total,
    this.isMe = false,
  });

  final String label;
  final int total;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final chipHeight = compact ? 42.0 : 54.0;
    final avatarRadius = compact ? 14.0 : 20.0;
    final fontSize = compact ? 12.0 : 15.0;

    return Container(
      height: chipHeight,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
      decoration: BoxDecoration(
        color: isMe ? AppColors.blue.withValues(alpha: 0.15) : AppColors.panel,
        borderRadius: BorderRadius.circular(chipHeight / 2),
        border: Border.all(
          color: isMe ? AppColors.blue : AppColors.line,
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: avatarRadius,
            backgroundColor: isMe
                ? AppColors.blue.withValues(alpha: 0.3)
                : const Color(0xFF28382F),
            child: Text(
              isMe ? '我' : label[0],
              style: TextStyle(
                color: AppColors.text,
                fontSize: fontSize - 2,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(width: compact ? 7 : 10),
          Flexible(
            child: Text(
              '$label ${total >= 0 ? '+' : ''}$total',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.text,
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
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

class _PileSlot extends StatelessWidget {
  const _PileSlot({
    required this.title,
    required this.subtitle,
    required this.score,
    required this.cards,
    this.onCardTap,
  });

  final String title;
  final String subtitle;
  final String score;
  final List<int> cards;
  final ValueChanged<PlayingCard>? onCardTap;

  @override
  Widget build(BuildContext context) {
    final text = AppTextTokens.of(context);
    return Container(
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.lineStrong, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: text.lg,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  score,
                  style: TextStyle(
                    color: score.startsWith('-')
                        ? AppColors.danger
                        : (score == '+0' || score == '0'
                            ? AppColors.dim
                            : AppColors.green),
                    fontSize: text.md,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.dim, fontSize: text.sm),
            ),
            const Spacer(),
            SizedBox(
              height: 74,
              child: CardHand(
                cards: [for (final id in cards) PlayingCard.standard(id)],
                onCardTap: onCardTap,
                draggable: true,
              ),
            ),
            const Spacer(),
          ],
        ),
    );
  }
}
