import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FeltTable extends StatelessWidget {
  const FeltTable({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(280),
        color: AppColors.felt,
        border: Border.all(color: AppColors.rail, width: 18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 80,
            offset: Offset(0, 34),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: children,
      ),
    );
  }
}

class PlayerSeat extends StatelessWidget {
  const PlayerSeat({
    super.key,
    required this.name,
    required this.subtitle,
    required this.initial,
    this.active = false,
    this.dealer = false,
    this.me = false,
  });

  final String name;
  final String subtitle;
  final String initial;
  final bool active;
  final bool dealer;
  final bool me;

  @override
  Widget build(BuildContext context) {
    final text = AppTextTokens.of(context);
    return Container(
      width: me ? 210 : 196,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: me ? AppColors.panelStrong : AppColors.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? AppColors.blue
              : dealer
                  ? AppColors.gold
                  : AppColors.line,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: me ? AppColors.gold : const Color(0xFF28382F),
            child: Text(
              initial,
              style: TextStyle(
                color: me ? AppColors.ink : AppColors.text,
                fontWeight: FontWeight.w900,
                fontSize: text.md,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: text.md,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.dim,
                    fontSize: text.sm,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (dealer) ...[
            const SizedBox(width: 8),
            Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '庄',
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: AppTextTokens.of(context).xs,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PhasePill extends StatelessWidget {
  const PhasePill({
    super.key,
    required this.game,
    required this.message,
  });

  final String game;
  final String message;

  @override
  Widget build(BuildContext context) {
    final text = AppTextTokens.of(context);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xBD060E0B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            game,
            style: TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w900,
              fontSize: text.md,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            message,
            style: TextStyle(color: AppColors.muted, fontSize: text.md),
          ),
        ],
      ),
    );
  }
}
