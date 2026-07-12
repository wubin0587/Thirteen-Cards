import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 圆形工具图标按钮 — 统一桌面右上角工具栏使用。
class GameToolIcon extends StatelessWidget {
  const GameToolIcon({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 38,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    // 纯浮层图标：无背景，仅靠阴影让图标在桌面上可见
    final button = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Icon(icon, color: AppColors.dim, size: size * 0.6),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
