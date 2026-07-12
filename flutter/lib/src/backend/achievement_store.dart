/// 十三水历史成就系统
///
/// 职责：
///   1. 定义所有成就（里程碑 & 首胜类）
///   2. 每局结束后检查是否解锁新成就
///   3. 持久化解锁记录到 JSON
///   4. 计算各成就的当前进度
library;

import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';

// ============================================================
//  成就分类
// ============================================================

enum AchievementCategory { first, milestone, special }

/// 单条成就的静态定义。
class AchievementDef {
  final String id;
  final String name;
  final String description;
  final String icon;
  final AchievementCategory category;
  final int? threshold; // 里程碑目标值

  const AchievementDef({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    this.threshold,
  });
}

/// 所有成就定义索引。
const kAllAchievements = <String, AchievementDef>{
  // ----------------------------------------------------------------
  //  首胜类（一次性的）
  // ----------------------------------------------------------------
  'first_win': AchievementDef(
    id: 'first_win',
    name: '初战告捷',
    description: '第一次赢下一局',
    icon: '🏆',
    category: AchievementCategory.first,
  ),
  'first_homerun': AchievementDef(
    id: 'first_homerun',
    name: '首次全垒打',
    description: '第一次全垒打',
    icon: '🏠',
    category: AchievementCategory.first,
  ),
  'first_shoot': AchievementDef(
    id: 'first_shoot',
    name: '首次打枪',
    description: '第一次打枪对手',
    icon: '🔫',
    category: AchievementCategory.first,
  ),
  'first_foul': AchievementDef(
    id: 'first_foul',
    name: '首次倒水',
    description: '第一次被判定倒水',
    icon: '💧',
    category: AchievementCategory.first,
  ),
  'big_win': AchievementDef(
    id: 'big_win',
    name: '大获全胜',
    description: '单局净胜 ≥ 50 水',
    icon: '💥',
    category: AchievementCategory.first,
  ),
  'first_special': AchievementDef(
    id: 'first_special',
    name: '天选之人',
    description: '第一次拿到特殊牌型（至尊清龙/一条龙等）',
    icon: '👑',
    category: AchievementCategory.first,
  ),
  // ----------------------------------------------------------------
  //  里程碑（梯度累积）
  // ----------------------------------------------------------------
  'wins_10': AchievementDef(
    id: 'wins_10',
    name: '常胜军',
    description: '累计赢 10 局',
    icon: '🎖️',
    category: AchievementCategory.milestone,
    threshold: 10,
  ),
  'wins_50': AchievementDef(
    id: 'wins_50',
    name: '百战先锋',
    description: '累计赢 50 局',
    icon: '🏅',
    category: AchievementCategory.milestone,
    threshold: 50,
  ),
  'wins_200': AchievementDef(
    id: 'wins_200',
    name: '常胜将军',
    description: '累计赢 200 局',
    icon: '🎗️',
    category: AchievementCategory.milestone,
    threshold: 200,
  ),
  'net_500': AchievementDef(
    id: 'net_500',
    name: '小有所成',
    description: '累计净胜 ≥ 500 水',
    icon: '🥉',
    category: AchievementCategory.milestone,
    threshold: 500,
  ),
  'net_2000': AchievementDef(
    id: 'net_2000',
    name: '千水之王',
    description: '累计净胜 ≥ 2,000 水',
    icon: '🥈',
    category: AchievementCategory.milestone,
    threshold: 2000,
  ),
  'net_10000': AchievementDef(
    id: 'net_10000',
    name: '万水归宗',
    description: '累计净胜 ≥ 10,000 水',
    icon: '🥇',
    category: AchievementCategory.milestone,
    threshold: 10000,
  ),
  'homerun_5': AchievementDef(
    id: 'homerun_5',
    name: '拆屋能手',
    description: '累计全垒打 5 次',
    icon: '🏚️',
    category: AchievementCategory.milestone,
    threshold: 5,
  ),
  'homerun_20': AchievementDef(
    id: 'homerun_20',
    name: '拆迁队长',
    description: '累计全垒打 20 次',
    icon: '🏘️',
    category: AchievementCategory.milestone,
    threshold: 20,
  ),
  'shoot_10': AchievementDef(
    id: 'shoot_10',
    name: '初露锋芒',
    description: '累计打枪 10 次',
    icon: '🎯',
    category: AchievementCategory.milestone,
    threshold: 10,
  ),
  'shoot_50': AchievementDef(
    id: 'shoot_50',
    name: '百步穿杨',
    description: '累计打枪 50 次',
    icon: '🎪',
    category: AchievementCategory.milestone,
    threshold: 50,
  ),
  'streak_3': AchievementDef(
    id: 'streak_3',
    name: '三连胜',
    description: '连续赢得 3 局',
    icon: '🔥',
    category: AchievementCategory.milestone,
    threshold: 3,
  ),
  'streak_5': AchievementDef(
    id: 'streak_5',
    name: '势如破竹',
    description: '连续赢得 5 局',
    icon: '🔥🔥',
    category: AchievementCategory.milestone,
    threshold: 5,
  ),
  'streak_10': AchievementDef(
    id: 'streak_10',
    name: '不败神话',
    description: '连续赢得 10 局',
    icon: '🔥🔥🔥',
    category: AchievementCategory.milestone,
    threshold: 10,
  ),
  // ----------------------------------------------------------------
  //  牌型成就（来自引擎，单副牌可获得的 5 种）
  // ----------------------------------------------------------------
  'dll_royal_flush': AchievementDef(
    id: 'dll_royal_flush',
    name: '至尊清龙',
    description: '拿到 Royal Straight Flush 13',
    icon: '👑',
    category: AchievementCategory.special,
  ),
  'dll_straight_13': AchievementDef(
    id: 'dll_straight_13',
    name: '一条龙',
    description: '拿到 Straight 13',
    icon: '🐉',
    category: AchievementCategory.special,
  ),
  'dll_twelve_royals': AchievementDef(
    id: 'dll_twelve_royals',
    name: '十二皇族',
    description: '拿到 Twelve Royals',
    icon: '👸',
    category: AchievementCategory.special,
  ),
  'dll_three_straight_flush': AchievementDef(
    id: 'dll_three_straight_flush',
    name: '三同花顺',
    description: '拿到 Three Straight Flush',
    icon: '♠️',
    category: AchievementCategory.special,
  ),
  'dll_three_four_kind': AchievementDef(
    id: 'dll_three_four_kind',
    name: '三分天下',
    description: '拿到 Three Four of a Kind',
    icon: '🔱',
    category: AchievementCategory.special,
  ),
};

// ============================================================
//  成就进度（运行时）
// ============================================================

/// 一条成就的运行时状态。
class AchievementState {
  final AchievementDef def;
  final bool unlocked;
  final DateTime? unlockedAt;
  final int progress; // 当前累积值（对里程碑有意义）
  final int? threshold;

  const AchievementState({
    required this.def,
    required this.unlocked,
    this.unlockedAt,
    required this.progress,
    this.threshold,
  });

  double get progressFraction =>
      threshold != null && threshold! > 0
          ? (progress / threshold!).clamp(0.0, 1.0)
          : (unlocked ? 1.0 : 0.0);
}

// ============================================================
//  成就存储器
// ============================================================

/// 本地成就存储 — JSON 文件持久化（与 score_tracker 同目录）。
class AchievementStore {
  AchievementStore({String? directory})
      : filePath = _buildPath(directory);

  static final AchievementStore instance = AchievementStore();

  final String filePath;

  /// 已解锁成就 ID → 解锁时间。
  Map<String, DateTime> _unlocked = {};
  bool _loaded = false;

  /// 上次计算过的统计快照（避免每次重新全量计算）。
  int _lastKnownWins = 0;
  int _lastKnownNet = 0;
  int _lastKnownHomeruns = 0;
  int _lastKnownShoots = 0;
  int _lastKnownStreak = 0;

  // ----------------------------------------------------------
  //  路径
  // ----------------------------------------------------------

  static String _buildPath(String? directory) {
    final dir = directory ?? AppPaths.dataDir();
    final sep = Platform.pathSeparator;
    return '$dir${sep}thirteen_achievements.json';
  }

  // ----------------------------------------------------------
  //  读取/写入
  // ----------------------------------------------------------

  Future<void> _ensure() async {
    if (_loaded) return;
    final file = File(filePath);
    if (await file.exists()) {
      try {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map && raw['unlocked'] is Map) {
          for (final entry in (raw['unlocked'] as Map).entries) {
            final ts = DateTime.tryParse('${entry.value}');
            if (ts != null) {
              _unlocked[entry.key.toString()] = ts;
            }
          }
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final file = File(filePath);
    final dir = file.parent;
    if (!await dir.exists()) await dir.create(recursive: true);
    final tmp = File('${filePath}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'game': 'thirteen',
        'unlocked': _unlocked.map(
          (k, v) => MapEntry(k, v.toIso8601String()),
        ),
      }),
    );
    await tmp.rename(filePath);
  }

  // ----------------------------------------------------------
  //  查询
  // ----------------------------------------------------------

  /// 获取所有成就的当前状态。
  Future<List<AchievementState>> getAllStates() async {
    await _ensure();
    return kAllAchievements.values.map((def) {
      final unlocked = _unlocked.containsKey(def.id);
      int progress = 0;
      if (def.category == AchievementCategory.milestone) {
        progress = _milestoneProgress(def.id);
      } else if (def.category == AchievementCategory.special) {
        progress = _specialHandCount;
      } else if (unlocked) {
        progress = 1;
      }
      return AchievementState(
        def: def,
        unlocked: unlocked,
        unlockedAt: _unlocked[def.id],
        progress: progress,
        threshold: def.threshold,
      );
    }).toList()
      ..sort((a, b) {
        // 已解锁的在前面，同分类内按阈值排序
        if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
        if (a.def.category != b.def.category) {
          return a.def.category.index.compareTo(b.def.category.index);
        }
        return (a.threshold ?? 0).compareTo(b.threshold ?? 0);
      });
  }

  /// 已解锁成就数量。
  Future<int> get unlockedCount async {
    await _ensure();
    return _unlocked.length;
  }

  /// 总成就数。
  int get totalCount => kAllAchievements.length;

  /// 是否已解锁某成就。
  Future<bool> isUnlocked(String id) async {
    await _ensure();
    return _unlocked.containsKey(id);
  }

  // ----------------------------------------------------------
  //  每局结束后检查
  // ----------------------------------------------------------

  /// 检查是否有新成就解锁，返回新解锁的成就 ID 列表。
  Future<List<String>> checkAfterRound({
    required int myNet,
    required bool isWin,
    required bool homerun,
    required bool fouled,
    required int shootCount,
    required bool hasSpecialHand,
    int dllAchievementsMask = 0, // DLL 成就位图
    // 以下从存储中计算
    int totalWins = 0,
    int totalNet = 0,
    int totalHomeruns = 0,
    int totalShoots = 0,
    int currentStreak = 0,
    int specialHandCount = 0,
  }) async {
    await _ensure();

    final newlyUnlocked = <String>[];
    void tryUnlock(String id) {
      if (!_unlocked.containsKey(id)) {
        _unlocked[id] = DateTime.now();
        newlyUnlocked.add(id);
      }
    }

    // 首胜类
    if (isWin) tryUnlock('first_win');
    if (myNet >= 50) tryUnlock('big_win');
    if (homerun) tryUnlock('first_homerun');
    if (shootCount > 0) tryUnlock('first_shoot');
    if (fouled) tryUnlock('first_foul');
    if (hasSpecialHand) tryUnlock('first_special');

    // 里程碑 — 阈值检查
    void checkMilestone(String id, int current) {
      final def = kAllAchievements[id];
      if (def == null || def.threshold == null) return;
      if (current >= def.threshold!) tryUnlock(id);
    }

    checkMilestone('wins_10', totalWins);
    checkMilestone('wins_50', totalWins);
    checkMilestone('wins_200', totalWins);
    checkMilestone('net_500', totalNet);
    checkMilestone('net_2000', totalNet);
    checkMilestone('net_10000', totalNet);
    checkMilestone('homerun_5', totalHomeruns);
    checkMilestone('homerun_20', totalHomeruns);
    checkMilestone('shoot_10', totalShoots);
    checkMilestone('shoot_50', totalShoots);
    checkMilestone('streak_3', currentStreak);
    checkMilestone('streak_5', currentStreak);
    checkMilestone('streak_10', currentStreak);

    // 牌型成就已在 DLL 位图段落处理

    // DLL 位图 — 每种特殊牌型单独解锁
    const dllBits = <int, String>{
      0: 'dll_royal_flush',
      1: 'dll_straight_13',
      2: 'dll_twelve_royals',
      3: 'dll_three_straight_flush',
      4: 'dll_three_four_kind',
    };
    for (final entry in dllBits.entries) {
      if ((dllAchievementsMask & (1 << entry.key)) != 0) {
        tryUnlock(entry.value);
      }
    }

    if (newlyUnlocked.isNotEmpty) await _save();
    return newlyUnlocked;
  }

  // ----------------------------------------------------------
  //  内部工具
  // ----------------------------------------------------------

  /// 从历史记录计算里程碑当前值。
  int _milestoneProgress(String id) {
    // 这些值在 checkAfterRound 时由外部注入，这里作为 fallback
    // 实际上从快照取
    switch (id) {
      case 'wins_10': case 'wins_50': case 'wins_200':
        return _lastKnownWins;
      case 'net_500': case 'net_2000': case 'net_10000':
        return _lastKnownNet;
      case 'homerun_5': case 'homerun_20':
        return _lastKnownHomeruns;
      case 'shoot_10': case 'shoot_50':
        return _lastKnownShoots;
      case 'streak_3': case 'streak_5': case 'streak_10':
        return _lastKnownStreak;
      default:
        return 0;
    }
  }

  int _specialHandCount = 0;

  /// 设置快照（每局结束时调用）。
  void updateSnapshot({
    required int wins,
    required int totalNet,
    required int homeruns,
    required int shoots,
    required int streak,
    int specialHandCount = 0,
  }) {
    _lastKnownWins = wins;
    _lastKnownNet = totalNet;
    _lastKnownHomeruns = homeruns;
    _lastKnownShoots = shoots;
    _lastKnownStreak = streak;
    _specialHandCount = specialHandCount;
  }

  /// 重置所有成就（调试用）。
  Future<void> reset() async {
    _unlocked = {};
    await _save();
  }
}
