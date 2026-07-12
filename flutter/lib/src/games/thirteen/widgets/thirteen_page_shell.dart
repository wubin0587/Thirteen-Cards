import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/action_controls.dart';
import '../../../widgets/game_tool_icon.dart';
import '../../../widgets/rules_sheet.dart';
import '../../../widgets/settings_sheet.dart';

// ============================================================
//  桌面舞台布局
// ============================================================

class TableStage extends StatelessWidget {
  const TableStage({
    super.key,
    required this.sideBoard,
    this.sideBoardWidth = 0.0,
    required this.phase,
    required this.table,
    required this.actionDock,
    required this.showActions,
    required this.toast,
    required this.handTitle,
    required this.handSubtitle,
    required this.hand,
    this.styleChips,
    this.settlementStatus,
    this.onStats,
  });

  final Widget sideBoard;
  final double sideBoardWidth;
  final Widget phase;
  final Widget table;
  final Widget actionDock;
  final bool showActions;
  final String toast;
  final String handTitle;
  final String handSubtitle;
  final Widget hand;
  final Widget? styleChips;
  final String? settlementStatus;
  final VoidCallback? onStats;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final compact = size.width < 760;
    final hasSideBoard = sideBoardWidth > 0;
    final tableRight = landscape && hasSideBoard ? sideBoardWidth + 16 : 8.0;
    final handHeight = landscape ? 126.0 : (compact ? 188.0 : 132.0);
    final tableTop = landscape ? 42.0 : 136.0;
    final actionHeight = showActions ? 58.0 : 0.0;
    final statusVisible = toast.isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.appBg,
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 8,
              top: 4,
              child: _BackButton(onPressed: () => Navigator.of(context).pop()),
            ),
            Positioned(
              right: 8,
              top: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onStats != null)
                    GameToolIcon(
                      icon: Icons.bar_chart_rounded,
                      tooltip: '战绩',
                      onTap: onStats!,
                    ),
                  if (onStats != null) const SizedBox(width: 6),
                  GameToolIcon(
                    icon: Icons.menu_book_rounded,
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const RulesSheet(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GameToolIcon(
                    icon: Icons.settings_rounded,
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const SettingsSheet(),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 82,
              top: 4,
              child: phase,
            ),
            if (!landscape)
              Positioned(
                left: 8,
                right: 8,
                top: 44,
                child: sideBoard,
              ),
            if (landscape && hasSideBoard)
              Positioned(
                right: 8,
                top: 44,
                width: sideBoardWidth,
                bottom: handHeight + actionHeight + 12,
                child: sideBoard,
              ),
            Positioned(
              left: 8,
              right: tableRight,
              top: tableTop,
              bottom: handHeight + actionHeight + 12,
              child: table,
            ),
            if (statusVisible)
              Positioned(
                left: landscape ? 92 : 12,
                top: 4,
                right: landscape ? 180 : 12,
                child: Center(child: _StatusBadge(text: toast)),
              ),
            if (settlementStatus != null && settlementStatus!.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: handHeight + actionHeight + 6,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _StatusBadge(text: settlementStatus!),
                  ),
                ),
              ),
            if (showActions)
              Positioned(
                right: 10,
                bottom: handHeight + 8,
                left: 10,
                child: actionDock,
              ),
            if (styleChips != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: handHeight + 8 + 44,
                height: 38,
                child: Center(child: styleChips!),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 6,
              height: handHeight,
              child: _HandRack(
                title: handTitle,
                subtitle: handSubtitle,
                child: hand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
//  返回按钮
// ============================================================

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_back_rounded, size: 20),
      label: const Text('返回',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
      style: FilledButton.styleFrom(
        minimumSize: const Size(80, 38),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        foregroundColor: AppColors.text,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.lineStrong),
        ),
      ),
    );
  }
}

// ============================================================
//  底部操作栏
// ============================================================

class ThirteenActionBar extends StatelessWidget {
  const ThirteenActionBar({
    super.key,
    required this.busy,
    required this.settled,
    required this.pilesFull,
    required this.onRecommend,
    required this.onUndo,
    required this.onSubmit,
    required this.onNewRound,
  });

  final bool busy;
  final bool settled;
  final bool pilesFull;
  final VoidCallback onRecommend;
  final VoidCallback onUndo;
  final VoidCallback onSubmit;
  final VoidCallback onNewRound;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (settled)
        GameButton(label: '🔄 新局', onPressed: busy ? null : onNewRound)
      else ...[
        GameButton(label: '🤖 推荐', onPressed: busy ? null : onRecommend),
        GameButton(label: '↩ 撤销', onPressed: busy ? null : onUndo),
        GameButton(
          label: pilesFull ? '提交' : '提交（未满）',
          variant: GameButtonVariant.primary,
          onPressed: busy || !pilesFull ? null : onSubmit,
        ),
      ],
    ];
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            buttons[i]
          ]
        ],
      ),
    );
  }
}

// ============================================================
//  风格标签
// ============================================================

class StyleChip extends StatelessWidget {
  const StyleChip({
    super.key,
    required this.label,
    this.recommended = false,
    this.onTap,
  });

  final String label;
  final bool recommended;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: recommended ? AppColors.gold : AppColors.lineStrong,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: recommended ? AppColors.ink : AppColors.text,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  状态标签
// ============================================================

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xDD070D0B),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: AppColors.danger, width: 3),
        ),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: AppTextTokens.of(context).md),
      ),
    );
  }
}

// ============================================================
//  手牌卡槽
// ============================================================

class _HandRack extends StatelessWidget {
  const _HandRack({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = AppTextTokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.panelStrong,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(8),
          bottom: Radius.circular(8),
        ),
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
        children: [
          SizedBox(
            height: compact ? 42 : 28,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: compact
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: text.md,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.dim,
                            fontSize: text.sm,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: text.md,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            subtitle,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.dim,
                              fontSize: text.sm,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
