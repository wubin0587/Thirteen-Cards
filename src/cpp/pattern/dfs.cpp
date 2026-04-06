/*=====================================================================
 *  src/cpp/pattern/dfs.cpp
 *  ---------------------------------------------------------------
 *  职责：
 *    枚举 13 张手牌中所有合法的"牌型独立集"，输出 Top-K 组合。
 *
 *  输出语义（HandCombo）：
 *    - units[]      : 识别出的有牌型单元，不指定墩位
 *                     card_count==3 → 只能放头墩
 *                     card_count==5 → 可放中墩或尾墩，由上层决定
 *    - loose_cards[]: 未锁入任何 unit 的散牌，按点数降序
 *    - typed_score  : units 分数之和（不含散牌墩评分）
 *
 *  上层模型职责：
 *    1. 枚举墩位分配（最多 3!=6 种排列）验证不倒水
 *    2. 将 loose_cards 填入空墩
 *    3. 综合期望分选最优方案
 *
 *  散牌约束（来自规则分析）：
 *    - 最坏情形：尾三条(5张墩位,3张有效) + 中散(5张) + 头散(3张) = 10 张散牌
 *    - 次坏：尾对子锁定(5张墩位) + 中散(5张) + 头散(3张) = 9 张散牌
 *    - 不可能全散（必然能组成至少一个牌型）
 *
 *  算法概述：
 *    Phase 1  枚举所有 C(13,3)+C(13,5) 候选（含散牌）, 标注牌型
 *    Phase 2  过滤：只保留 rank_order > 1 的有牌型候选
 *    Phase 3  DFS 选独立集（bitmask 冲突剪枝）
 *             - 最多选 1 个 3张候选 + 2 个 5张候选
 *             - 已选满对应槽位时跳过同槽候选（剪枝）
 *    Phase 4  对每个完整独立集验证不倒水可行性（枚举排列，O(6)）
 *    Phase 5  按 typed_score 维护 Top-K 堆
 *
 *  复杂度：
 *    候选枚举  O(C(13,3)+C(13,5)) = O(1573)
 *    DFS 节点  最坏 O(2^N)，实际因 13张牌 bitmask 约束和槽位剪枝
 *              可行节点数远小于理论上界，实测 < 5ms
 *====================================================================*/

#include "pattern.h"
#include "cards.h"
#include "score.h"

#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <stdbool.h>

/* ====================================================================
 *  内部常量
 * ==================================================================== */
#define MAX_CAND3      300    /* C(13,3)=286 */
#define MAX_CAND5     1300    /* C(13,5)=1287 */
#define ALL_13_MASK  0x1FFF   /* 13位全1 */
#define MAX_K_LIMIT   128     /* combo数组上限，与 DFSCandResult.combos 对齐 */

/* ====================================================================
 *  内部：候选牌型节点
 * ==================================================================== */
typedef struct {
    uint16_t mask;        /* 哪些槽位被占用（bit i = hand13[i]） */
    int      card_count;  /* 3 或 5 */
    int      rank_order;
    int      score;
    int      tiebreak;
    int      cards[5];    /* 实际牌号 */
    HandResult result;
} Cand;

/* ====================================================================
 *  工具
 * ==================================================================== */
static int int_desc_cmp(const void *a, const void *b)
{
    return *(const int*)b - *(const int*)a;
}

static int cand_score_desc(const void *a, const void *b)
{
    const Cand *ca = (const Cand*)a, *cb = (const Cand*)b;
    if (cb->score != ca->score) return cb->score - ca->score;
    return cb->rank_order - ca->rank_order;
}

static int combo_score_desc(const void *a, const void *b)
{
    return ((const HandCombo*)b)->typed_score -
           ((const HandCombo*)a)->typed_score;
}

static int encode_tiebreak(const int ranks[], int n)
{
    int code = 0;
    for (int i = 0; i < n; ++i) code = (code << 4) | (ranks[i] & 0xF);
    return code;
}

static int calc_tiebreak(const int *card_ids, int n, int rank_order)
{
    int ranks[5];
    for (int i = 0; i < n; ++i) ranks[i] = card_rank(card_ids[i]);

    /* 降序 */
    for (int i = 0; i < n-1; ++i)
        for (int j = i+1; j < n; ++j)
            if (ranks[j] > ranks[i]) { int t=ranks[i]; ranks[i]=ranks[j]; ranks[j]=t; }

    /* 散牌/顺子/同花/同花顺：直接点数序 */
    if (rank_order <= 1 || rank_order == 5 ||
        rank_order == 6  || rank_order == 9)
        return encode_tiebreak(ranks, n);

    /* 其他：出现频次高的点数靠前，频次相同则大点数靠前 */
    int cnt[13] = {0};
    for (int i = 0; i < n; ++i) cnt[ranks[i]]++;
    for (int i = 0; i < n-1; ++i)
        for (int j = i+1; j < n; ++j) {
            int ci = cnt[ranks[i]], cj = cnt[ranks[j]];
            if (cj > ci || (cj == ci && ranks[j] > ranks[i])) {
                int t=ranks[i]; ranks[i]=ranks[j]; ranks[j]=t;
            }
        }
    return encode_tiebreak(ranks, n);
}

/* ====================================================================
 *  Phase 1: 枚举候选
 *  仅收录 rank_order > 1 的有牌型候选（散牌由剩余牌自动成为 loose）
 * ==================================================================== */
static void enum_cands(
    const int *hand13,
    int start, int depth, int need,
    int position, int chosen[5],
    Cand *out, int *cnt, int max_cnt)
{
    if (depth == need) {
        if (*cnt >= max_cnt) return;

        int card_ids[5];
        for (int i = 0; i < need; ++i) card_ids[i] = hand13[chosen[i]];

        HandResult hr = search_pattern(position, card_ids, need);
        if (hr.rank_order <= 1) return; /* 散牌不收录 */

        uint16_t mask = 0;
        for (int i = 0; i < need; ++i) mask |= (uint16_t)(1u << chosen[i]);

        Cand c;
        c.mask       = mask;
        c.card_count = need;
        c.rank_order = hr.rank_order;
        c.score      = hr.score;
        c.tiebreak   = calc_tiebreak(card_ids, need, hr.rank_order);
        c.result     = hr;
        for (int i = 0; i < need; ++i) c.cards[i] = card_ids[i];
        if (need == 3) c.cards[3] = c.cards[4] = 0;

        out[(*cnt)++] = c;
        return;
    }
    int remaining = need - depth;
    for (int i = start; i <= 12 - remaining + 1; ++i) {
        chosen[depth] = i;
        enum_cands(hand13, i+1, depth+1, need, position,
                   chosen, out, cnt, max_cnt);
    }
}

/* ====================================================================
 *  Phase 4: 不倒水结构可行性验证
 *
 *  不倒水约束：tail >= middle >= head（rank_order 比较）
 *  card_count==3 的 unit 只能放头墩；card_count==5 只能放中/尾墩。
 *
 *  空墩（散牌墩）的 rank_order 在 DFS 阶段未知，
 *  但必然 <= 已选 unit 中最弱的 rank_order
 *  （若散牌能组成更强牌型，那组牌会在候选池中被选入）。
 *  因此此处做"乐观可行性"判断：
 *    - 散牌墩强度取"乐观上界" = 0（不对有牌型unit的顺序构成威胁）
 *    - 仅验证有牌型unit之间的相对顺序是否存在合法排列
 *
 *  例外情况（1个size5 + 1个size3）：
 *    唯一分配：头=s3, 尾=s5, 中=散牌
 *    中散牌墩强度上界 = min(s5, 所有散牌能组成的最强牌型)
 *    由于无法精确知道散牌强度，做乐观假设：
 *      若 s5[0] >= s3[0]，认为中墩散牌可能满足 s3[0] <= 散牌 <= s5[0]
 *      → 返回 true（上层精确验证时再剔除不合法的）
 *    若 s5[0] < s3[0]：尾 < 头，结构上必然倒水 → 返回 false
 *
 *  返回 true 表示结构上"可能合法"（乐观），false 表示"必然倒水"。
 * ==================================================================== */
static bool check_no_topple(const HandUnit *units, int unit_count)
{
    if (unit_count == 0) return true;
    if (unit_count == 1) return true; /* 单unit，空墩填散牌，必然合法 */

    int s3[3], s3_cnt = 0;
    int s5[3], s5_cnt = 0;

    for (int i = 0; i < unit_count; ++i) {
        if (units[i].card_count == 3)
            s3[s3_cnt++] = units[i].result.rank_order;
        else
            s5[s5_cnt++] = units[i].result.rank_order;
    }

    if (s3_cnt > 1 || s5_cnt > 2) return false; /* 防御 */

    if (s5_cnt == 2 && s3_cnt == 0) {
        /*
         *  头=散牌，中=min(s5)，尾=max(s5)
         *  不倒水：max(s5) >= min(s5)（恒成立）且 min(s5) >= 散牌头
         *  散牌头强度 <= min(s5)（否则散牌那组牌应被候选池收录）→ 恒成立
         */
        return true;
    }

    if (s5_cnt == 1 && s3_cnt == 1) {
        /*
         *  唯一分配：头=s3[0], 中=散牌, 尾=s5[0]
         *  不倒水需要：s5[0] >= 散牌中 >= s3[0]
         *  散牌中的实际强度未知，但：
         *    若 s5[0] < s3[0]：尾rank < 头rank，无论中墩如何必然倒水
         *    若 s5[0] >= s3[0]：乐观认为散牌中强度可落在[s3[0], s5[0]]区间
         *                       → 可能合法，返回 true，由上层精确验证
         */
        return s5[0] >= s3[0];
    }

    if (s5_cnt == 2 && s3_cnt == 1) {
        /*
         *  头=s3[0], 中=min(s5), 尾=max(s5)
         *  不倒水：max(s5) >= min(s5) >= s3[0]
         *  max >= min 恒成立；只需验证 min(s5) >= s3[0]
         */
        int sml = (s5[0] < s5[1]) ? s5[0] : s5[1];
        return sml >= s3[0];
    }

    return true;
}

/* ====================================================================
 *  Top-K 维护：插入一个新 combo，维护按 typed_score 降序的 top-k 列表
 * ==================================================================== */
static void topk_insert(HandCombo *arr, int *cnt, int max_k,
                         const HandCombo *item)
{
    if (*cnt < max_k) {
        arr[(*cnt)++] = *item;
        /* 插入排序维护有序（小数组，可接受） */
        for (int i = *cnt-1; i > 0 &&
             arr[i].typed_score > arr[i-1].typed_score; --i) {
            HandCombo t = arr[i]; arr[i] = arr[i-1]; arr[i-1] = t;
        }
    } else if (item->typed_score > arr[max_k-1].typed_score) {
        arr[max_k-1] = *item;
        /* 重新插入排序 */
        for (int i = max_k-1; i > 0 &&
             arr[i].typed_score > arr[i-1].typed_score; --i) {
            HandCombo t = arr[i]; arr[i] = arr[i-1]; arr[i-1] = t;
        }
    }
}

/* ====================================================================
 *  DFS 上下文
 * ==================================================================== */
typedef struct {
    const int *hand13;

    /* 候选池：分3张/5张两组，按score降序 */
    Cand cand3[MAX_CAND3];
    int  cnt3;
    Cand cand5[MAX_CAND5];
    int  cnt5;

    /* 当前已选 units（最多3个） */
    HandUnit selected[3];
    int      sel_count;
    int      sel_3cnt;  /* 已选的3张unit数量，最多1 */
    int      sel_5cnt;  /* 已选的5张unit数量，最多2 */
    uint16_t used_mask; /* 已用牌的位掩码 */
    int      typed_score_acc; /* 已选unit分数累计 */

    /* 输出 */
    HandCombo *out_arr;
    int       *out_cnt;
    int        max_k;
} DFSCtx;

/* ====================================================================
 *  构建 HandCombo 并尝试插入 Top-K
 * ==================================================================== */
static void try_emit(DFSCtx *ctx)
{
    /* 验证不倒水 */
    if (!check_no_topple(ctx->selected, ctx->sel_count)) return;

    HandCombo combo;
    combo.unit_count  = ctx->sel_count;
    combo.typed_score = ctx->typed_score_acc;

    for (int i = 0; i < ctx->sel_count; ++i)
        combo.units[i] = ctx->selected[i];

    /* 收集散牌 */
    combo.loose_count = 0;
    uint16_t loose_mask = (uint16_t)(ALL_13_MASK ^ ctx->used_mask);
    for (int i = 0; i < 13; ++i)
        if (loose_mask & (1u << i))
            combo.loose_cards[combo.loose_count++] = ctx->hand13[i];

    /* 散牌按点数降序排列 */
    qsort(combo.loose_cards, (size_t)combo.loose_count,
          sizeof(int), int_desc_cmp);

    topk_insert(ctx->out_arr, ctx->out_cnt, ctx->max_k, &combo);
}

/* ====================================================================
 *  DFS 核心：在候选池中选独立集
 *
 *  候选按 score 降序排列，遍历时：
 *    - 先枚举3张候选池（已选0个3张时）
 *    - 再枚举5张候选池（已选<2个5张时）
 *    - 每次"选入"或"跳过"当前候选
 *    - bitmask冲突时直接跳过
 *
 *  剪枝：
 *    1. 冲突剪枝：候选mask与used_mask有交集
 *    2. 槽位满剪枝：已选1个3张则不再选3张；已选2个5张则不再选5张
 *    3. 上界剪枝：当前typed_score_acc + 剩余所有候选最高分 <= top-k末尾分数
 *       （只在 out_cnt==max_k 时激活）
 *
 *  每次进入DFS时先尝试emit当前状态（选入已选unit，当前位置作为"不再选"的终止）
 * ==================================================================== */

/* 上界：当前已选分 + 候选池中从idx开始分数最高的若干牌的总和（宽松上界） */
static int upper_bound_5(const DFSCtx *ctx, int idx5)
{
    /* 最多还能选 (2-sel_5cnt) 个5张 和 (1-sel_3cnt) 个3张 */
    int slots5 = 2 - ctx->sel_5cnt;
    int slots3 = 1 - ctx->sel_3cnt;
    int ub = ctx->typed_score_acc;

    /* 5张候选从 idx5 开始取前 slots5 个（已按score降序） */
    int taken5 = 0;
    for (int i = idx5; i < ctx->cnt5 && taken5 < slots5; ++i) {
        if (ctx->cand5[i].mask & ctx->used_mask) continue;
        ub += ctx->cand5[i].score;
        ++taken5;
    }
    /* 3张候选取前 slots3 个 */
    int taken3 = 0;
    for (int i = 0; i < ctx->cnt3 && taken3 < slots3; ++i) {
        if (ctx->cand3[i].mask & ctx->used_mask) continue;
        ub += ctx->cand3[i].score;
        ++taken3;
    }
    return ub;
}

static void dfs(DFSCtx *ctx, int idx5)
{
    /* 每进入一次节点先尝试emit（当前已选集合作为一个候选组合） */
    if (ctx->sel_count >= 1)
        try_emit(ctx);

    /* 槽位已满：3张满(1) 且 5张满(2)，不能再选 */
    if (ctx->sel_3cnt >= 1 && ctx->sel_5cnt >= 2) return;

    /* 上界剪枝（Top-K已满时才启用） */
    if (*ctx->out_cnt >= ctx->max_k) {
        int ub = upper_bound_5(ctx, idx5);
        int worst_topk = ctx->out_arr[*ctx->out_cnt - 1].typed_score;
        if (ub <= worst_topk) return;
    }

    /* ---- 枚举5张候选池（idx5 开始） ---- */
    if (ctx->sel_5cnt < 2) {
        for (int i = idx5; i < ctx->cnt5; ++i) {
            const Cand *c = &ctx->cand5[i];
            if (c->mask & ctx->used_mask) continue; /* 冲突跳过 */

            /* 选入 c */
            HandUnit *u = &ctx->selected[ctx->sel_count];
            u->card_count = 5;
            memcpy(u->cards, c->cards, 5*sizeof(int));
            u->result = c->result;

            ctx->sel_count++;
            ctx->sel_5cnt++;
            ctx->used_mask        = (uint16_t)(ctx->used_mask | c->mask);
            ctx->typed_score_acc += c->score;

            dfs(ctx, i + 1); /* 下一个5张从 i+1 开始（避免重复选同一个） */

            /* 回溯 */
            ctx->sel_count--;
            ctx->sel_5cnt--;
            ctx->used_mask        = (uint16_t)(ctx->used_mask ^ c->mask);
            ctx->typed_score_acc -= c->score;
        }
    }

    /* ---- 枚举3张候选池（每次从头扫，但每条DFS路径最多选1个） ---- */
    if (ctx->sel_3cnt < 1) {
        for (int i = 0; i < ctx->cnt3; ++i) {
            const Cand *c = &ctx->cand3[i];
            if (c->mask & ctx->used_mask) continue;

            HandUnit *u = &ctx->selected[ctx->sel_count];
            u->card_count = 3;
            memcpy(u->cards, c->cards, 5*sizeof(int));
            u->result = c->result;

            ctx->sel_count++;
            ctx->sel_3cnt++;
            ctx->used_mask        = (uint16_t)(ctx->used_mask | c->mask);
            ctx->typed_score_acc += c->score;

            /* 选入3张后，5张候选从当前 idx5 继续枚举 */
            dfs(ctx, idx5);

            ctx->sel_count--;
            ctx->sel_3cnt--;
            ctx->used_mask        = (uint16_t)(ctx->used_mask ^ c->mask);
            ctx->typed_score_acc -= c->score;
        }
    }
}

/* ====================================================================
 *  顶层接口：dfs_enum_combos
 * ==================================================================== */
int dfs_enum_combos(const int hand13[13], DFSCandResult *out, int max_k)
{
    if (!hand13 || !out) return -1;
    memset(out, 0, sizeof(DFSCandResult));

    if (max_k <= 0)   max_k = 64;
    if (max_k > MAX_K_LIMIT) max_k = MAX_K_LIMIT;

    /* ── 0. 特殊牌型检测 ─────────────────────────────────────────── */
    HandResult hr_sp = search_pattern(3, hand13, 13);
    if (hr_sp.position == 3 && hr_sp.score > 0) {
        out->is_special    = 1;
        out->special_score = hr_sp.score;
        out->special_name  = hr_sp.hand_name;
        return 0;
    }

    /* ── 1. 枚举候选池 ──────────────────────────────────────────── */
    DFSCtx ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.hand13    = hand13;
    ctx.out_arr   = out->combos;
    ctx.out_cnt   = &out->combo_count;
    ctx.max_k     = max_k;

    int chosen[5];

    /* 3张候选：position=0(头墩) */
    enum_cands(hand13, 0,0,3, 0, chosen,
               ctx.cand3, &ctx.cnt3, MAX_CAND3);

    /* 5张候选：position=2(尾墩) 枚举，score使用尾墩分数；
     * 注意：同一组5张牌在中墩/尾墩的score不同。
     * 策略：同时枚举中墩(pos=1)和尾墩(pos=2)候选，作为独立节点。
     * 上层收到 result.position 后可知候选是哪个墩位评分，
     * 也可忽略位置让模型重新评估。
     *
     * 为保持简洁：分别枚举 pos=1 和 pos=2，合并去重（相同mask取score高者）。
     */
    Cand cand5_tail[MAX_CAND5];
    int  cnt5_tail = 0;
    Cand cand5_mid[MAX_CAND5];
    int  cnt5_mid  = 0;

    enum_cands(hand13, 0,0,5, 2, chosen,
               cand5_tail, &cnt5_tail, MAX_CAND5);
    enum_cands(hand13, 0,0,5, 1, chosen,
               cand5_mid,  &cnt5_mid,  MAX_CAND5);

    /*
     *  合并5张候选：相同 mask 的中/尾候选，保留 score 较高的一个。
     *  若两者 score 不同，只保留高分（上层模型知道 result.position 可还原）。
     *  若需保留两个版本供模型选择，也可以都放入（注释中的替代逻辑）。
     *
     *  当前策略：相同mask只保留score最高者，避免候选池膨胀。
     */
    ctx.cnt5 = 0;
    /* 先放尾墩候选 */
    for (int i = 0; i < cnt5_tail; ++i)
        ctx.cand5[ctx.cnt5++] = cand5_tail[i];

    /* 再合并中墩候选：找相同mask的，若中墩分更高则替换 */
    for (int i = 0; i < cnt5_mid; ++i) {
        bool found = false;
        for (int j = 0; j < ctx.cnt5; ++j) {
            if (ctx.cand5[j].mask == cand5_mid[i].mask) {
                if (cand5_mid[i].score > ctx.cand5[j].score) {
                    ctx.cand5[j] = cand5_mid[i];
                }
                found = true;
                break;
            }
        }
        if (!found && ctx.cnt5 < MAX_CAND5)
            ctx.cand5[ctx.cnt5++] = cand5_mid[i];
    }

    /* 按score降序排序候选池（用于上界剪枝和快速建立高分下界） */
    qsort(ctx.cand3, (size_t)ctx.cnt3, sizeof(Cand), cand_score_desc);
    qsort(ctx.cand5, (size_t)ctx.cnt5, sizeof(Cand), cand_score_desc);

    /* ── 2. DFS 搜索 ────────────────────────────────────────────── */
    dfs(&ctx, 0);

    /* ── 3. 最终按 typed_score 降序排列输出 ──────────────────────── */
    qsort(out->combos, (size_t)out->combo_count,
          sizeof(HandCombo), combo_score_desc);

    return 0;
}
