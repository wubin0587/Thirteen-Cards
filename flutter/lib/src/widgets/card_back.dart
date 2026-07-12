import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'card_tile.dart';

// ============================================================
//  牌背
// ============================================================

/// 单张牌背 — 深蓝底 + ♠ 半透明花纹。
class CardBack extends StatelessWidget {
  const CardBack({
    super.key,
    this.width = 64,
    this.height = 88,
    this.rotation = 0,
    this.borderWidth = 2,
  });

  final double width;
  final double height;
  final double rotation;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation * math.pi / 180,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF1A3A5C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF2A5A8C),
            width: borderWidth,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x44000000),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '♠',
            style: TextStyle(
              color: const Color(0xFF2A5A8C).withValues(alpha: 0.5),
              fontSize: width * 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  叠放牌背（与 CardHand 同重叠算法）
// ============================================================

/// 叠放的多张牌背，自动计算重叠步进。
class StackedCardBacks extends StatelessWidget {
  const StackedCardBacks({
    super.key,
    required this.count,
    this.metrics,
  });

  final int count;
  final CardMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final m = metrics ?? CardMetrics.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        const minStep = 18.0;
        final normalStep = m.width + gap;
        final normalTotal = m.width + normalStep * (count - 1);
        final step = normalTotal <= constraints.maxWidth
            ? normalStep
            : ((constraints.maxWidth - m.width) / (count - 1))
                .clamp(minStep, normalStep);
        final totalW = m.width + step * (count - 1);

        return SizedBox(
          width: totalW,
          height: m.height + 8,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < count; i++)
                Positioned(
                  left: i * step,
                  bottom: 0,
                  child: CardBack(
                    width: m.width,
                    height: m.height,
                    borderWidth: 1.5,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
//  重叠步进算法（供 CardHand / StackedCardBacks 共享）
// ============================================================

/// 计算卡片重叠时每张牌的步进宽度。
///
/// [cardWidth] 单张牌宽，[count] 张数，[availableWidth] 可用宽度。
double computeCardStep(
  double cardWidth,
  int count,
  double availableWidth, {
  double normalGap = 6,
  double minStep = 16,
}) {
  if (count <= 1) return 0;
  final normalStep = cardWidth + normalGap;
  final normalTotal = cardWidth + normalStep * (count - 1);
  return normalTotal <= availableWidth
      ? normalStep
      : ((availableWidth - cardWidth) / (count - 1)).clamp(minStep, normalStep);
}
