import 'package:flutter/material.dart';

import '../../../app/game_module.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/card_back.dart';
import '../../../widgets/game_tool_icon.dart';
import '../../../widgets/rules_sheet.dart';
import '../../../widgets/settings_sheet.dart';
import '../../../widgets/stats_sheet.dart';

/// 十三水大厅 — 全屏 felt 桌面，中央牌背 + 开始按钮，右上角工具。
class ThirteenLobby extends StatelessWidget {
  const ThirteenLobby({super.key, required this.module});
  final GameModule module;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final text = AppTextTokens.of(context);

    return Scaffold(
      backgroundColor: AppColors.appBg,
      body: Stack(
        children: [
          // 中央内容
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题
                Text(
                  module.title,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  module.subtitle,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: text.lg,
                  ),
                ),
                const SizedBox(height: 36),
                _DeckPreview(),
                const SizedBox(height: 44),
                _StartButton(onTap: () => _start(context)),
              ],
            ),
          ),
          // 右上角工具栏
          Positioned(
            top: topPad + 12,
            right: 16,
            child: _Toolbar(),
          ),
        ],
      ),
    );
  }

  void _start(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => module.builder(ctx, module.defaultPlayerCount),
      ),
    );
  }
}

// ============================================================
//  中央牌背预览
// ============================================================

class _DeckPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.14,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 4; i++)
            Padding(
              padding: EdgeInsets.only(left: i > 0 ? -20 : 0),
              child: const CardBack(),
            ),
        ],
      ),
    );
  }
}

// ============================================================
//  开始按钮
// ============================================================

class _StartButton extends StatelessWidget {
  const _StartButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.play_arrow_rounded, size: 32),
        label: const Text('开始游戏',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF0A5C3A),
          foregroundColor: AppColors.text,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.gold, width: 2),
          ),
          shadowColor: AppColors.gold.withValues(alpha: 0.3),
          elevation: 8,
        ),
      ),
    );
  }
}

// ============================================================
//  右上角工具栏
// ============================================================

class _Toolbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GameToolIcon(
          icon: Icons.bar_chart_rounded,
          tooltip: '战绩',
          size: 40,
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const StatsSheet(),
          ),
        ),
        const SizedBox(width: 6),
        GameToolIcon(
          icon: Icons.menu_book_rounded,
          tooltip: '规则',
          size: 40,
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const RulesSheet(),
          ),
        ),
        const SizedBox(width: 6),
        GameToolIcon(
          icon: Icons.settings_rounded,
          tooltip: '设置',
          size: 40,
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const SettingsSheet(),
          ),
        ),
      ],
    );
  }
}
