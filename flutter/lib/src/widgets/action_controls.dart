import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum GameButtonVariant { normal, primary, danger }

class GameButton extends StatelessWidget {
  const GameButton({
    super.key,
    required this.label,
    this.variant = GameButtonVariant.normal,
    this.onPressed,
  });

  final String label;
  final GameButtonVariant variant;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final text = AppTextTokens.of(context);
    final colors = switch (variant) {
      GameButtonVariant.primary => (
          bg: AppColors.gold,
          fg: AppColors.ink,
          border: AppColors.gold,
        ),
      GameButtonVariant.danger => (
          bg: Colors.transparent,
          fg: AppColors.danger,
          border: AppColors.danger,
        ),
      GameButtonVariant.normal => (
          bg: Colors.white.withValues(alpha: 0.06),
          fg: AppColors.text,
          border: AppColors.lineStrong,
        ),
    };

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: Size(0, MediaQuery.sizeOf(context).width < 760 ? 58 : 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: colors.bg,
        foregroundColor: colors.fg,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.04),
        disabledForegroundColor: AppColors.dim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border),
        ),
        textStyle: TextStyle(
          fontSize: text.md,
          fontWeight:
              variant == GameButtonVariant.normal ? FontWeight.w600 : FontWeight.w900,
        ),
      ),
      child: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class ActionDock extends StatelessWidget {
  const ActionDock({
    super.key,
    required this.children,
    this.fullWidth = false,
  });

  final List<Widget> children;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 44,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class DockLabel extends StatelessWidget {
  const DockLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.dim,
          fontSize: AppTextTokens.of(context).sm,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class DockGrid extends StatelessWidget {
  const DockGrid({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final child in children) SizedBox(width: 120, child: child)],
      ),
    );
  }
}
