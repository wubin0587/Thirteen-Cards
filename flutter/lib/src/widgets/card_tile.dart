import 'package:flutter/material.dart';

import '../models/card_model.dart';
import '../theme/app_theme.dart';

/// 统一卡牌尺寸，供 [CardTile] 和 [CardHand] 共用。
class CardMetrics {
  const CardMetrics({required this.width, required this.height});

  final double width;
  final double height;

  /// 根据屏幕环境算出合适的牌尺寸。
  static CardMetrics of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscapePhone = size.width > size.height && size.height < 520;
    final compact = size.width < 760;
    if (landscapePhone) return const CardMetrics(width: 38, height: 54);
    return CardMetrics(
      width: compact ? 44 : 54,
      height: compact ? 64 : 78,
    );
  }

  /// 翻牌结算、牌堆预览等纯装饰场景的紧凑尺寸。
  static const compact = CardMetrics(width: 36, height: 52);
}

/// 单张扑克牌展示。
///
/// 只负责"显示牌面 + 响应点击"，不包含推荐标记、拖拽、红五高亮等功能。
class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.card,
    this.selected = false,
    this.disabled = false,
    this.onTap,
    this.metrics,
  });

  final PlayingCard card;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;
  final CardMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics ?? CardMetrics.of(context);
    final text = AppTextTokens.of(context);
    final color = card.isBigJoker || (!card.isJoker && card.suit.isRed)
        ? AppColors.suitRed
        : AppColors.suitBlack;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      offset: selected ? const Offset(0, -0.16) : Offset.zero,
      child: Opacity(
        opacity: disabled ? 0.52 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: m.width,
            height: m.height,
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: selected ? AppColors.blue : AppColors.paperEdge,
                width: selected ? 2 : 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 16,
                  offset: Offset(0, 9),
                ),
              ],
            ),
            child: Stack(
              children: [
                // 左上角点数
                Positioned(
                  top: 5,
                  left: 6,
                  child: Text(
                    card.rankLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: text.cardRank,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
                // 左上角花色
                Positioned(
                  top: 5 + text.cardRank + 2,
                  left: 7,
                  child: Text(
                    card.suitLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: text.cardSuit,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
                // 中央大花色
                Center(
                  child: Text(
                    card.suitLabel,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.18),
                      fontSize: text.cardCenter,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
