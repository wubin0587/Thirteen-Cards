import 'package:flutter/widgets.dart';

import '../models/card_model.dart';

/// 游戏模块描述 — 大厅通过此接口展示卡片，不依赖具体游戏实现。
class GameModule {
  const GameModule({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.previewCards,
    required this.builder,
    this.playerCountOptions = const [4],
    this.defaultPlayerCount = 4,
    this.historyBuilder,
    this.singleLobbyBuilder,
  });

  final String id;
  final String title;
  final String subtitle;

  /// 大厅卡片上展示的示例牌（通常 4 张）。
  final List<PlayingCard> previewCards;

  /// 可选玩家人数列表（用于人数选择弹窗）。
  final List<int> playerCountOptions;
  final int defaultPlayerCount;

  /// 创建游戏页面。
  final Widget Function(BuildContext, int playerCount) builder;

  /// 历史页入口（null 时不显示历史按钮）。
  final WidgetBuilder? historyBuilder;

  /// 单游戏模式时使用的大厅组件。
  /// null 时回退为 [CombinedGameLobby]。
  final WidgetBuilder? singleLobbyBuilder;
}
