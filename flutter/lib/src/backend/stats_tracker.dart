import 'dart:ffi';

import 'thirteen/thirteen_ffi.dart';

/// 统计管理器 — 桥接 DLL PlayerStats 和 Dart JSON 存储。
///
/// PlayerStats 负责总分和成就的实时累计（DLL 内部维护），
/// ThirteenScoreStore 负责对局详情（手牌名、标签等）的持久化。
class StatsTracker {
  StatsTracker._();

  static final StatsTracker instance = StatsTracker._();

  Pointer<Void>? _handle;

  // Dart 侧追踪（DLL PlayerStats 不包含这些字段）
  int _homerunCount = 0;
  int _foulCount = 0;
  int _totalShootCount = 0;

  /// 初始化 DLL 统计跟踪（在 main 启动时调用）。
  void init() {
    _handle = ThirteenCardsFfi.statsCreate('玩家');
  }

  /// 释放 DLL 资源。
  void dispose() {
    if (_handle != null) {
      ThirteenCardsFfi.statsDestroy(_handle!);
      _handle = null;
    }
  }

  /// 记录一局，同步写入 DLL PlayerStats。
  void recordRound(int netScore, {
    int achievementsMask = 0,
    bool homerun = false,
    bool fouled = false,
    int shootCount = 0,
  }) {
    if (_handle != null) {
      ThirteenCardsFfi.statsAddRound(_handle!, netScore);
      if (achievementsMask > 0) {
        ThirteenCardsFfi.statsSetAchievements(_handle!, achievementsMask);
      }
    }
    if (homerun) _homerunCount++;
    if (fouled) _foulCount++;
    _totalShootCount += shootCount;
  }

  /// 全垒打次数。
  int get homerunCount => _homerunCount;
  /// 倒水次数。
  int get foulCount => _foulCount;
  /// 累计打枪次数。
  int get totalShootCount => _totalShootCount;

  /// 累计总分（来自 DLL）。
  int get totalScore =>
      _handle != null ? ThirteenCardsFfi.statsTotalScore(_handle!) : 0;

  /// 总局数（来自 DLL）。
  int get roundCount =>
      _handle != null ? ThirteenCardsFfi.statsRoundCount(_handle!) : 0;

  /// 局均分
  double get avgScore =>
      roundCount > 0 ? totalScore / roundCount : 0.0;

  /// 第 idx 局得分（来自 DLL）。
  int roundScore(int idx) =>
      _handle != null ? ThirteenCardsFfi.statsRoundScore(_handle!, idx) : 0;

  /// 成就位图（来自 DLL）。
  int get achievements =>
      _handle != null ? ThirteenCardsFfi.statsAchievements(_handle!) : 0;

  /// 检查是否拥有某成就。
  bool hasAchievement(int bit) =>
      (achievements & (1 << bit)) != 0;

  /// 成就列表（中文名）。
  static const achievementNames = {
    0: '至尊清龙',
    1: '一条龙',
    2: '十二皇族',
    3: '三同花顺',
    4: '三分天下',
    5: '中墩五同',
    6: '尾墩五同',
  };

  /// 已解锁的成就名称列表。
  List<String> get unlockedAchievements =>
      achievementNames.entries
          .where((e) => hasAchievement(e.key))
          .map((e) => e.value)
          .toList();
}
