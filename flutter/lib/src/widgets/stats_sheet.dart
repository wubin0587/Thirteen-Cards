import 'package:flutter/material.dart';

import '../backend/achievement_store.dart';
import '../backend/score_tracker.dart';
import '../backend/stats_tracker.dart';
import '../models/card_model.dart';
import '../theme/app_theme.dart';
import '../widgets/card_hand.dart';
import '../widgets/card_tile.dart';

// 成就分段常量
const _tabAll = 0;
const _tabUnlocked = 1;
const _tabLocked = 2;

/// 战绩面板 — 统计摘要 + 成就图鉴 + 对局历史。
class StatsSheet extends StatefulWidget {
  const StatsSheet({super.key});

  @override
  State<StatsSheet> createState() => _StatsSheetState();
}

class _StatsSheetState extends State<StatsSheet> {
  ThirteenStats _stats = ThirteenStats.empty;
  List<ThirteenRoundRecord> _records = const [];
  bool _loading = true;
  int _dllTotal = 0;
  int _dllGames = 0;
  int _homerunCount = 0;
  int _foulCount = 0;
  int _totalShootCount = 0;
  List<AchievementState> _achStates = const [];
  int _achUnlocked = 0;
  int _achTotal = 0;

  // 分段索引
  int _tabIndex = _tabAll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ThirteenScoreStore.instance;
    final stats = await store.getStats();
    final records = await store.getAll();
    final tracker = StatsTracker.instance;
    final achStore = AchievementStore.instance;
    final achStates = await achStore.getAllStates();
    final achUnlocked = await achStore.unlockedCount;
    if (mounted) {
      setState(() {
        _stats = stats;
        _records = records;
        _dllTotal = tracker.totalScore;
        _dllGames = tracker.roundCount;
        _homerunCount = tracker.homerunCount;
        _foulCount = tracker.foulCount;
        _totalShootCount = tracker.totalShootCount;
        _achStates = achStates;
        _achUnlocked = achUnlocked;
        _achTotal = achStore.totalCount;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTextTokens.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.panelStrong,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 拖拽手柄
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.dim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.bar_chart_rounded,
                        color: AppColors.gold, size: 28),
                    const SizedBox(width: 10),
                    Text('战绩',
                        style: TextStyle(
                            fontSize: text.lg, fontWeight: FontWeight.w900)),
                    if (!_loading) ...[
                      const SizedBox(width: 8),
                      Text('$_achUnlocked/$_achTotal',
                          style: TextStyle(
                              color: AppColors.gold,
                              fontSize: text.xs,
                              fontWeight: FontWeight.w700)),
                    ],
                    const Spacer(),
                    if (!_loading && _records.isNotEmpty)
                      TextButton.icon(
                        onPressed: _confirmClear,
                        icon: Icon(Icons.delete_outline,
                            color: AppColors.danger, size: 18),
                        label: Text('清空',
                            style: TextStyle(
                                color: AppColors.danger, fontSize: text.sm)),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: AppColors.dim,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.line, height: 1),

              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_records.isEmpty)
                Expanded(child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sports_esports_outlined,
                          color: AppColors.dim, size: 48),
                      const SizedBox(height: 12),
                      Text('暂无对局记录',
                          style: TextStyle(color: AppColors.dim, fontSize: text.sm)),
                      const SizedBox(height: 4),
                      Text('开始一局游戏，成就将在自动解锁',
                          style: TextStyle(color: AppColors.dim, fontSize: text.xs)),
                    ],
                  ),
                ))
              else
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      // 统计摘要卡片
                      _StatsSummary(
                        stats: _stats,
                        dllTotal: _dllTotal,
                        dllGames: _dllGames,
                        homerunCount: _homerunCount,
                        foulCount: _foulCount,
                        totalShootCount: _totalShootCount,
                        text: text,
                      ),
                      const SizedBox(height: 16),
                      // 成就图鉴
                      _AchievementGallery(
                        states: _achStates,
                        unlockedCount: _achUnlocked,
                        totalCount: _achTotal,
                        tabIndex: _tabIndex,
                        onTabChanged: (i) => setState(() => _tabIndex = i),
                        text: text,
                      ),
                      const SizedBox(height: 16),
                      // 对局列表
                      Text('对局记录',
                          style: TextStyle(
                              fontSize: text.sm,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted)),
                      const SizedBox(height: 8),
                      for (final r in _records)
                        _RecordRow(record: r, text: text),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelStrong,
        title: const Text('清空记录', style: TextStyle(color: AppColors.text)),
        content: const Text('确定要清空所有对局记录吗？此操作不可恢复。成就记录不受影响。',
            style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: TextStyle(color: AppColors.dim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清空',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ThirteenScoreStore.instance.clear();
      if (mounted) _load();
    }
  }
}

// ============================================================
//  统计摘要
// ============================================================

class _StatsSummary extends StatelessWidget {
  const _StatsSummary({
    required this.stats,
    required this.dllTotal,
    required this.dllGames,
    required this.homerunCount,
    required this.foulCount,
    required this.totalShootCount,
    required this.text,
  });
  final ThirteenStats stats;
  final int dllTotal;
  final int dllGames;
  final int homerunCount;
  final int foulCount;
  final int totalShootCount;
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    final total = dllGames > 0 ? dllTotal : stats.totalNet;
    final games = dllGames > 0 ? dllGames : stats.games;
    final avg = games > 0 ? total / games : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _StatItem(
                label: '总局数',
                value: '$games',
                text: text,
              ),
              _StatDivider(),
              _StatItem(
                label: '累计净分',
                value: total >= 0 ? '+$total' : '$total',
                color: total >= 0 ? AppColors.green : AppColors.danger,
                text: text,
              ),
              _StatDivider(),
              _StatItem(
                label: '胜率',
                value: '${(stats.winRate * 100).toStringAsFixed(0)}%',
                text: text,
              ),
              _StatDivider(),
              _StatItem(
                label: '均分',
                value: avg >= 0
                    ? '+${avg.toStringAsFixed(1)}'
                    : avg.toStringAsFixed(1),
                color: avg >= 0 ? AppColors.green : AppColors.danger,
                text: text,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniStat(label: '🏠 全垒打', value: '$homerunCount'),
              const SizedBox(width: 16),
              _MiniStat(label: '🔫 打枪', value: '$totalShootCount'),
              const SizedBox(width: 16),
              _MiniStat(label: '倒水', value: '$foulCount'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                color: AppColors.dim,
                fontSize: AppTextTokens.of(context).xs)),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(
              color: AppColors.text,
              fontSize: AppTextTokens.of(context).sm,
              fontWeight: FontWeight.w900,
            )),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    this.color,
    required this.text,
  });
  final String label;
  final String value;
  final Color? color;
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.dim, fontSize: text.xs)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                color: color ?? AppColors.text,
                fontSize: text.lg,
                fontWeight: FontWeight.w900,
              )),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: AppColors.line,
    );
  }
}

// ============================================================
//  成就图鉴
// ============================================================

class _AchievementGallery extends StatelessWidget {
  const _AchievementGallery({
    required this.states,
    required this.unlockedCount,
    required this.totalCount,
    required this.tabIndex,
    required this.onTabChanged,
    required this.text,
  });

  final List<AchievementState> states;
  final int unlockedCount;
  final int totalCount;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    final filtered = states.where((s) {
      if (tabIndex == _tabUnlocked) return s.unlocked;
      if (tabIndex == _tabLocked) return !s.unlocked;
      return true;
    }).toList();

    final firstCount = states.where((s) => s.def.category == AchievementCategory.first && s.unlocked).length;
    final firstTotal = states.where((s) => s.def.category == AchievementCategory.first).length;
    final mileUnlocked = states.where((s) => s.def.category == AchievementCategory.milestone && s.unlocked).length;
    final mileTotal = states.where((s) => s.def.category == AchievementCategory.milestone).length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Icon(Icons.emoji_events_rounded,
                    color: AppColors.gold, size: 20),
                const SizedBox(width: 8),
                Text('成就图鉴',
                    style: TextStyle(
                        color: AppColors.gold,
                        fontSize: text.sm,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('$unlockedCount / $totalCount',
                    style: TextStyle(
                        color: AppColors.dim,
                        fontSize: text.xs,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          // 分类进度小标签
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(
              children: [
                _CategoryPill(
                  icon: '🏅',
                  label: '首胜',
                  progress: '$firstCount/$firstTotal',
                ),
                const SizedBox(width: 8),
                _CategoryPill(
                  icon: '🎯',
                  label: '里程碑',
                  progress: '$mileUnlocked/$mileTotal',
                ),
              ],
            ),
          ),
          // 分段标签
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                _TabChip(label: '全部', selected: tabIndex == _tabAll, onTap: () => onTabChanged(_tabAll)),
                const SizedBox(width: 6),
                _TabChip(label: '已解锁', selected: tabIndex == _tabUnlocked, onTap: () => onTabChanged(_tabUnlocked)),
                const SizedBox(width: 6),
                _TabChip(label: '未解锁', selected: tabIndex == _tabLocked, onTap: () => onTabChanged(_tabLocked)),
              ],
            ),
          ),
          // 成就网格
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(tabIndex == _tabUnlocked ? '还没有解锁的成就' : '所有成就已解锁',
                    style: TextStyle(color: AppColors.dim, fontSize: text.xs)),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 3.8,
                children: filtered.map((s) => _AchievementTile(state: s, text: text)).toList(),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.icon,
    required this.label,
    required this.progress,
  });
  final String icon;
  final String label;
  final String progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppTextTokens.of(context).xs,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text(progress,
              style: TextStyle(
                  color: AppColors.gold,
                  fontSize: AppTextTokens.of(context).xs,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : AppColors.panel,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.ink : AppColors.muted,
            fontSize: AppTextTokens.of(context).xs,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.state, required this.text});
  final AchievementState state;
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    final unlocked = state.unlocked;
    final fg = unlocked ? AppColors.text : AppColors.dim;
    final bg = unlocked
        ? AppColors.gold.withValues(alpha: 0.12)
        : AppColors.panel;

    return Tooltip(
      message: state.def.description,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: unlocked
                ? AppColors.gold.withValues(alpha: 0.3)
                : AppColors.line,
          ),
        ),
        child: Row(
          children: [
            Text(
              unlocked ? state.def.icon : '🔒',
              style: TextStyle(fontSize: 14, color: unlocked ? null : AppColors.dim),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          state.def.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fg,
                            fontSize: text.xs,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (unlocked) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.check_circle_rounded, color: AppColors.green, size: 11),
                      ],
                    ],
                  ),
                  if (state.def.category == AchievementCategory.milestone &&
                      state.threshold != null) ...[
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: state.progressFraction,
                        backgroundColor: AppColors.panelStrong,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          unlocked ? AppColors.gold : AppColors.dim,
                        ),
                        minHeight: 2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
//  单条记录（可展开）
// ============================================================

class _RecordRow extends StatefulWidget {
  const _RecordRow({required this.record, required this.text});
  final ThirteenRoundRecord record;
  final AppTextTokens text;

  @override
  State<_RecordRow> createState() => _RecordRowState();
}

class _RecordRowState extends State<_RecordRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final date = _formatDate(r.time);
    final isWin = r.myNet > 0;
    final netStr = r.myNet >= 0 ? '+${r.myNet}' : '${r.myNet}';
    final netColor = isWin ? AppColors.green : AppColors.danger;

    // 标签
    final tags = <Widget>[];
    if (r.shootCount > 0) {
      tags.add(_Tag('🔫${r.shootCount}', AppColors.gold));
    }
    if (r.homerun) {
      tags.add(_Tag('🏠', AppColors.gold));
    }
    if (r.fouled) {
      tags.add(_Tag('倒水', AppColors.danger));
    }
    if (r.specialName.isNotEmpty) {
      tags.add(_Tag(r.specialName, AppColors.blue));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Text(date,
                      style: TextStyle(
                          color: AppColors.dim,
                          fontSize: widget.text.sm,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ])),
                  const SizedBox(width: 12),
                  Text(netStr,
                      style: TextStyle(
                          color: netColor,
                          fontSize: widget.text.md,
                          fontWeight: FontWeight.w900,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ])),
                  const Spacer(),
                  ...tags,
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.dim,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          // 展开详情
          if (_expanded) ...[
            const Divider(height: 1, color: AppColors.line),
            _PileDetail(record: r, text: widget.text),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    return '${dt.month}/${dt.day}';
  }
}

/// 展开后的墩位详情
class _PileDetail extends StatelessWidget {
  const _PileDetail({required this.record, required this.text});
  final ThirteenRoundRecord record;
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final hasPile = r.headHand != null || r.middleHand != null || r.tailHand != null;

    if (r.specialName.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Text('特殊牌型：${r.specialName}',
            style: TextStyle(
                color: AppColors.blue,
                fontSize: text.sm,
                fontWeight: FontWeight.w700)),
      );
    }

    if (!hasPile) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PileCell(
                  label: '头墩',
                  hand: r.headHand,
                  score: r.headScore,
                  cards: r.headCards,
                  text: text),
              const SizedBox(width: 8),
              _PileCell(
                  label: '中墩',
                  hand: r.middleHand,
                  score: r.middleScore,
                  cards: r.middleCards,
                  text: text),
              const SizedBox(width: 8),
              _PileCell(
                  label: '尾墩',
                  hand: r.tailHand,
                  score: r.tailScore,
                  cards: r.tailCards,
                  text: text),
            ],
          ),
        ],
      ),
    );
  }
}

class _PileCell extends StatelessWidget {
  const _PileCell({
    required this.label,
    required this.hand,
    required this.score,
    this.cards,
    required this.text,
  });
  final String label;
  final String? hand;
  final int? score;
  final List<int>? cards;
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.panelStrong,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(
                        color: AppColors.dim,
                        fontSize: text.xs)),
                if (hand != null) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(hand!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.text,
                            fontSize: text.sm,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
                if (score != null) ...[
                  const SizedBox(width: 4),
                  Text('$score 水',
                      style: TextStyle(
                          color: AppColors.gold,
                          fontSize: text.xs,
                          fontWeight: FontWeight.w800)),
                ],
              ],
            ),
            if (cards != null && cards!.isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: CardMetrics.compact.height + 12,
                child: CardHand(
                  cards: cards!.map(PlayingCard.standard).toList(),
                  metrics: CardMetrics.compact,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _Tag(String text, Color color) {
  return Container(
    margin: const EdgeInsets.only(left: 4),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(text,
        style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800)),
  );
}
