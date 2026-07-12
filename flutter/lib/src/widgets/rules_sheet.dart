import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 十三水规则说明 — 新手友好版。
class RulesSheet extends StatelessWidget {
  const RulesSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final text = AppTextTokens.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
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
                    Icon(Icons.menu_book_rounded,
                        color: AppColors.gold, size: 28),
                    const SizedBox(width: 10),
                    Text('游戏规则',
                        style: TextStyle(
                            fontSize: text.lg, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: AppColors.dim,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.line, height: 1),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  children: [
                    _QuickStart(text: text),
                    const SizedBox(height: 20),
                    _HowToPlay(text: text),
                    const SizedBox(height: 20),
                    _HandTypes(text: text),
                    const SizedBox(height: 20),
                    _SpecialHands(text: text),
                    const SizedBox(height: 20),
                    _Scoring(text: text),
                    const SizedBox(height: 20),
                    _FoulRule(text: text),
                  ],
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
//  速览
// ============================================================

class _QuickStart extends StatelessWidget {
  const _QuickStart({required this.text});
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('⚡ 一句话', style: TextStyle(fontSize: text.md, fontWeight: FontWeight.w900, color: AppColors.gold)),
          ]),
          const SizedBox(height: 8),
          Text(
            '把自己 13 张牌分成三墩（头墩3张、中墩5张、尾墩5张），'
            '每墩的牌型越强越好。和每个对手三墩逐一比较，'
            '赢得越多水（分）越多。',
            style: TextStyle(fontSize: text.sm, color: AppColors.text, height: 1.6),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⚠️ 重要：尾墩必须 > 中墩 > 头墩（牌型从强到弱），否则判"倒水"买单！',
                    style: TextStyle(fontSize: text.xs, color: AppColors.danger, height: 1.4, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  玩法
// ============================================================

class _HowToPlay extends StatelessWidget {
  const _HowToPlay({required this.text});
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    return _SectionTitle(title: '🎯 怎么玩', text: text);
  }
}

// ============================================================
//  牌型大全
// ============================================================

class _HandTypes extends StatelessWidget {
  const _HandTypes({required this.text});
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: '🃏 牌型等级（从低到高）', text: text),
        const SizedBox(height: 8),
        Text('中墩和尾墩用以下等级比较，头墩只有 高牌/对子/三条：',
            style: TextStyle(fontSize: text.xs, color: AppColors.muted, height: 1.4)),
        const SizedBox(height: 8),
        _HandTier(
          tiers: const [
            _Tier(name: '高牌（乌龙）', desc: '啥也没有，单张最大', icon: '🫥', baseScore: '1 水'),
            _Tier(name: '一对', desc: '两张相同点数', icon: '2️⃣', baseScore: '1 水'),
            _Tier(name: '两对', desc: '两组对子', icon: '🤝', baseScore: '1 水'),
            _Tier(name: '三条', desc: '三张相同点数', icon: '3️⃣', baseScore: '1 水'),
            _Tier(name: '顺子', desc: '五张连续点数', icon: '🔢', baseScore: '1 水'),
            _Tier(name: '同花', desc: '五张同花色', icon: '🌸', baseScore: '1 水'),
            _Tier(name: '葫芦', desc: '三条 + 一对', icon: '🏠', baseScore: '中墩 2 / 尾墩 1'),
            _Tier(name: '铁支（四条）', desc: '四张相同点数', icon: '💎', baseScore: '中墩 8 / 尾墩 4'),
            _Tier(name: '同花顺', desc: '同花色且连续', icon: '🌟', baseScore: '中墩 10 / 尾墩 5'),
          ],
          text: text,
        ),
        const SizedBox(height: 12),
        Text('头墩只有 3 张牌：高牌(1水) / 对子(1水) / 三条(3水)',
            style: TextStyle(fontSize: text.xs, color: AppColors.muted, fontStyle: FontStyle.italic)),
      ],
    );
  }
}

// ============================================================
//  特殊牌型
// ============================================================

class _SpecialHands extends StatelessWidget {
  const _SpecialHands({required this.text});
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: '👑 特殊牌型（发牌时直接结算）', text: text),
        const SizedBox(height: 4),
        Text('拿到以下 13 张牌的组合时，不用摆墩直接赢：',
            style: TextStyle(fontSize: text.xs, color: AppColors.muted, height: 1.4)),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            children: [
              _SpecialRow(name: '三顺子', desc: '三墩各自是顺子', score: '6'),
              _Divider(),
              _SpecialRow(name: '三同花', desc: '三墩各自是同花', score: '6'),
              _Divider(),
              _SpecialRow(name: '六对半', desc: '6 个对子 + 1 张单牌', score: '6'),
              _Divider(),
              _SpecialRow(name: '五对三条', desc: '5 个对子 + 1 个三条', score: '6'),
              _Divider(),
              _SpecialRow(name: '四套三条', desc: '4 个三条', score: '6'),
              _Divider(),
              _SpecialRow(name: '凑一色', desc: '13 张全红或全黑', score: '10'),
              _Divider(),
              _SpecialRow(name: '全小', desc: '所有牌点数 2~8', score: '10'),
              _Divider(),
              _SpecialRow(name: '全大', desc: '所有牌点数 8~A', score: '10'),
              _Divider(),
              _SpecialRow(name: '三分天下', desc: '3 个铁支（四个头）', score: '20'),
              _Divider(),
              _SpecialRow(name: '三同花顺', desc: '三墩都是同花顺', score: '20'),
              _Divider(),
              _SpecialRow(name: '十二皇族', desc: '12 张 J/Q/K/A', score: '24'),
              _Divider(),
              _SpecialRow(name: '一条龙', desc: 'A~K 各一张，不花色', score: '36'),
              _Divider(),
              _SpecialRow(name: '至尊清龙', desc: 'A~K 同一花色', score: '108'),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
//  计分
// ============================================================

class _Scoring extends StatelessWidget {
  const _Scoring({required this.text});
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: '💰 算分方法', text: text),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepRow(num: '1', text: '和每个对手的对应墩比较——头墩 vs 头墩、中墩 vs 中墩、尾墩 vs 尾墩'),
              const SizedBox(height: 8),
              _StepRow(num: '2', text: '牌型等级高的一方赢，获得该墩的"基础水数"'),
              const SizedBox(height: 8),
              _StepRow(num: '3', text: '如果某墩平局，互相不得分'),
              const SizedBox(height: 8),
              _StepRow(num: '4', text: '某人三墩全赢你 → "打枪"，输赢 ×2'),
              const SizedBox(height: 8),
              _StepRow(num: '5', text: '某人对所有其他人都打枪 → "全垒打"，输赢 ×3'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: AppColors.gold, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('举例：你尾墩拿到同花顺(5水)，对手尾墩只是同花(1水)，你赢走 5 水。如果还有全垒打(×3)，就是 15 水。',
                          style: TextStyle(fontSize: text.xs, color: AppColors.gold, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
//  倒水规则
// ============================================================

class _FoulRule extends StatelessWidget {
  const _FoulRule({required this.text});
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: '🚫 倒水（乌龙）', text: text),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '摆墩时，三墩的牌型强度必须依次递增：',
                style: TextStyle(fontSize: text.sm, color: AppColors.text, height: 1.5),
              ),
              const SizedBox(height: 12),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MiniPile(label: '头墩', color: AppColors.danger),
                    Icon(Icons.arrow_forward, color: AppColors.gold, size: 18),
                    _MiniPile(label: '中墩', color: AppColors.gold),
                    Icon(Icons.arrow_forward, color: AppColors.gold, size: 18),
                    _MiniPile(label: '尾墩', color: AppColors.green),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('尾墩 ≥ 中墩 ≥ 头墩（牌型只能越来越强，不能倒退）',
                  style: TextStyle(fontSize: text.xs, color: AppColors.muted)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '❌ 如果头墩是中墩的对子，但尾墩只是高牌→倒水！\n'
                  '❌ 如果中墩是同花，但头墩比中墩强→倒水！\n'
                  '倒水的玩家要为所有赢家买单。',
                  style: TextStyle(fontSize: text.xs, color: AppColors.danger, height: 1.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
//  子组件
// ============================================================

class _MiniPile extends StatelessWidget {
  const _MiniPile({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13)),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.text});
  final String title;
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: TextStyle(fontSize: text.md, fontWeight: FontWeight.w900, color: AppColors.gold));
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.num, required this.text});
  final String num;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22, height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.gold,
            shape: BoxShape.circle,
          ),
          child: Text(num,
              style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w900, fontSize: 12)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: AppTextTokens.of(context).xs, color: AppColors.text, height: 1.5)),
        ),
      ],
    );
  }
}

class _HandTier extends StatelessWidget {
  const _HandTier({required this.tiers, required this.text});
  final List<_Tier> tiers;
  final AppTextTokens text;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < tiers.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Text(tiers[i].icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(tiers[i].name,
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: text.sm, color: AppColors.text)),
                            const Spacer(),
                            Text(tiers[i].baseScore,
                                style: TextStyle(fontSize: text.xs, color: AppColors.gold, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        Text(tiers[i].desc,
                            style: TextStyle(fontSize: text.xs, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpecialRow extends StatelessWidget {
  const _SpecialRow({required this.name, required this.desc, required this.score});
  final String name;
  final String desc;
  final String score;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.text)),
                Text(desc, style: TextStyle(fontSize: AppTextTokens.of(context).xs, color: AppColors.muted)),
              ],
            ),
          ),
          Text('$score 水', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.gold)),
        ],
      ),
    );
  }
}

class _Tier {
  final String name;
  final String desc;
  final String icon;
  final String baseScore;
  const _Tier({required this.name, required this.desc, required this.icon, required this.baseScore});
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: AppColors.line.withValues(alpha: 0.4));
  }
}
