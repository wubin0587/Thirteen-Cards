/*=====================================================================
 *  src/cpp/pattern/dfs.cpp
 *  ---------------------------------------------------------------
 *  职责边界：
 *    - DFS 负责找出"让有牌型墩分数最大化"的最优锁定方案
 *    - 散牌分配不做决策，结构化输出给上层策略层
 *
 *  散牌约束（来自规则分析）：
 *    - 13张牌必然含至少一个可升档牌型（否则是一条龙特殊牌型）
 *    - 最坏情形：尾墩三条(3张) + 中墩5散 + 头墩3散 = 10张散牌
 *    - 次坏情形：尾墩对子(2张锁定于5张墩位) + 剩余全散 = 9张散牌
 *    - typed_piles 至少有1个有效条目（is_special=0时）
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
#define MAX_TAIL_CANDS   1300
#define MAX_MID_CANDS    1300   /* C(13,5)=1287，修正之前的截断bug */
#define MEMO_SIZE        8192
#define INVALID_SCORE    -32767
#define ALL_13_MASK      0x1FFF

/* ====================================================================
 *  候选牌型结构（内部用）
 * ==================================================================== */
typedef struct {
    uint16_t mask;
    int      rank_order;
    int      score;
    int      tiebreak;
} HandCand;

/* ====================================================================
 *  工具函数
 * ==================================================================== */
static int int_desc_cmp(const void *a, const void *b)
{
    return *(const int*)b - *(const int*)a;
}

static int encode_tiebreak(const int ranks[], int n)
{
    int code = 0;
    for (int i = 0; i < n; ++i) code = (code << 4) | (ranks[i] & 0xF);
    return code;
}

static int calc_tiebreak(const int *card_ids, int n)
{
    int ranks[5];
    for (int i = 0; i < n; ++i) ranks[i] = card_rank(card_ids[i]);
    qsort(ranks, (size_t)n, sizeof(int), int_desc_cmp);
    return encode_tiebreak(ranks, n);
}

static int calc_tiebreak_typed(const int *card_ids, int n, int rank_order)
{
    int ranks[5];
    for (int i = 0; i < n; ++i) ranks[i] = card_rank(card_ids[i]);
    qsort(ranks, (size_t)n, sizeof(int), int_desc_cmp);

    /* 顺子/同花/散牌/同花顺：直接按点数序编码 */
    if (rank_order == 1 || rank_order == 5 ||
        rank_order == 6 || rank_order == 9) {
        return encode_tiebreak(ranks, n);
    }

    /* 其他牌型（对子/两对/三条/葫芦/四条）：
     * 重排：出现次数多的点数放前面，次数相同则大点数放前面
     * 保证两对、葫芦等的副特征也参与比较 */
    int rank_cnt[13] = {0};
    for (int i = 0; i < n; ++i) rank_cnt[ranks[i]]++;

    for (int i = 0; i < n - 1; ++i) {
        for (int j = i + 1; j < n; ++j) {
            int ci = rank_cnt[ranks[i]], cj = rank_cnt[ranks[j]];
            if (cj > ci || (cj == ci && ranks[j] > ranks[i])) {
                int t = ranks[i]; ranks[i] = ranks[j]; ranks[j] = t;
            }
        }
    }
    return encode_tiebreak(ranks, n);
}

static inline bool hand_ge(int ra, int ta, int rb, int tb)
{
    return (ra != rb) ? ra > rb : ta >= tb;
}

/* ====================================================================
 *  候选池枚举
 * ==================================================================== */
static void enum_comb(
    const int *hand13, int start, int depth, int need,
    int position, int chosen[5],
    HandCand *out, int *out_cnt, int max_cnt)
{
    if (depth == need) {
        if (*out_cnt >= max_cnt) return;

        int card_ids[5];
        for (int i = 0; i < need; ++i) card_ids[i] = hand13[chosen[i]];

        HandResult hr = search_pattern(position, card_ids, need);

        uint16_t mask = 0;
        for (int i = 0; i < need; ++i) mask |= (uint16_t)(1u << chosen[i]);

        HandCand c;
        c.mask       = mask;
        c.rank_order = hr.rank_order;
        c.score      = hr.score;
        c.tiebreak   = (hr.rank_order <= 1)
                       ? calc_tiebreak(card_ids, need)
                       : calc_tiebreak_typed(card_ids, need, hr.rank_order);
        out[(*out_cnt)++] = c;
        return;
    }
    int remaining = need - depth;
    for (int i = start; i <= 12 - remaining + 1; ++i) {
        chosen[depth] = i;
        enum_comb(hand13, i+1, depth+1, need, position,
                  chosen, out, out_cnt, max_cnt);
    }
}

static int cand_desc_cmp(const void *a, const void *b)
{
    const HandCand *ca = (const HandCand*)a, *cb = (const HandCand*)b;
    if (cb->rank_order != ca->rank_order) return cb->rank_order - ca->rank_order;
    return cb->tiebreak - ca->tiebreak;
}

/* ====================================================================
 *  头墩评估（3张剩余牌直接计算）
 * ==================================================================== */
static HandCand eval_head(const int *hand13, uint16_t head_mask)
{
    int card_ids[3], n = 0;
    for (int i = 0; i < 13; ++i)
        if (head_mask & (1u << i)) card_ids[n++] = hand13[i];

    HandResult hr = search_pattern(0, card_ids, 3);
    HandCand c;
    c.mask       = head_mask;
    c.rank_order = hr.rank_order;
    c.score      = hr.score;
    c.tiebreak   = (hr.rank_order <= 1)
                   ? calc_tiebreak(card_ids, 3)
                   : calc_tiebreak_typed(card_ids, 3, hr.rank_order);
    return c;
}

/* ====================================================================
 *  DFS 上下文
 * ==================================================================== */
typedef struct {
    const int *hand13;

    HandCand tail_cands[MAX_TAIL_CANDS];
    int      tail_cnt;
    HandCand mid_cands[MAX_MID_CANDS];
    int      mid_cnt;

    /* memo[used_mask] = 从该used_mask出发，中墩+头墩能得的最优分
     * INVALID_SCORE 表示未计算 */
    int16_t  memo_score[MEMO_SIZE];
    uint16_t memo_mid_mask[MEMO_SIZE];

    int      best_total;
    uint16_t best_tail_mask;
    uint16_t best_mid_mask;
} DFSContext;

/* ====================================================================
 *  DFS 内层：搜索中墩（记忆化）
 * ==================================================================== */
static void dfs_mid(
    DFSContext *ctx,
    uint16_t    used_after_tail,
    int         tail_rank, int tail_tb,
    int         tail_score)
{
    if (ctx->memo_score[used_after_tail] != (int16_t)INVALID_SCORE) {
        int candidate = tail_score + (int)ctx->memo_score[used_after_tail];
        if (candidate > ctx->best_total) {
            ctx->best_total    = candidate;
            ctx->best_tail_mask = used_after_tail;
            ctx->best_mid_mask  = ctx->memo_mid_mask[used_after_tail];
        }
        return;
    }

    int      local_best     = INVALID_SCORE;
    uint16_t local_best_mid = 0;

    for (int mi = 0; mi < ctx->mid_cnt; ++mi) {
        const HandCand *mc = &ctx->mid_cands[mi];

        if (mc->mask & used_after_tail) continue;
        if (!hand_ge(tail_rank, tail_tb, mc->rank_order, mc->tiebreak)) continue;

        uint16_t used_after_mid = used_after_tail | mc->mask;
        uint16_t head_mask      = (uint16_t)(ALL_13_MASK ^ used_after_mid);
        HandCand hc = eval_head(ctx->hand13, head_mask);

        if (!hand_ge(mc->rank_order, mc->tiebreak, hc.rank_order, hc.tiebreak)) continue;

        int total = mc->score + hc.score;

        /* 保守上界：头墩最高3水（三条） */
        if (local_best != INVALID_SCORE && total + 3 <= local_best) continue;

        if (total > local_best) {
            local_best     = total;
            local_best_mid = mc->mask;
        }
    }

    ctx->memo_score[used_after_tail]    = (int16_t)(local_best == INVALID_SCORE ? 0 : local_best);
    ctx->memo_mid_mask[used_after_tail] = local_best_mid;

    if (local_best != INVALID_SCORE) {
        int candidate = tail_score + local_best;
        if (candidate > ctx->best_total) {
            ctx->best_total    = candidate;
            ctx->best_mid_mask = local_best_mid;
        }
    }
}

/* ====================================================================
 *  DFS 外层：枚举尾墩
 * ==================================================================== */
static void dfs_tail(DFSContext *ctx)
{
    /* 第一遍：有牌型尾墩优先，快速建立高分下界 */
    for (int ti = 0; ti < ctx->tail_cnt; ++ti) {
        if (ctx->tail_cands[ti].rank_order <= 1) continue;
        int prev = ctx->best_total;
        dfs_mid(ctx, ctx->tail_cands[ti].mask,
                ctx->tail_cands[ti].rank_order,
                ctx->tail_cands[ti].tiebreak,
                ctx->tail_cands[ti].score);
        if (ctx->best_total > prev)
            ctx->best_tail_mask = ctx->tail_cands[ti].mask;
    }

    /* 第二遍：全量（含散牌尾墩），上界剪枝 */
    for (int ti = 0; ti < ctx->tail_cnt; ++ti) {
        const HandCand *tc = &ctx->tail_cands[ti];
        if (tc->score + 10 + 3 <= ctx->best_total) break;
        int prev = ctx->best_total;
        dfs_mid(ctx, tc->mask, tc->rank_order, tc->tiebreak, tc->score);
        if (ctx->best_total > prev)
            ctx->best_tail_mask = tc->mask;
    }
}

/* ====================================================================
 *  从位图还原牌id列表
 * ==================================================================== */
static int mask_to_cards(const int *hand13, uint16_t mask, int *out)
{
    int n = 0;
    for (int i = 0; i < 13; ++i)
        if (mask & (1u << i)) out[n++] = hand13[i];
    return n;
}

/* ====================================================================
 *  顶层接口
 * ==================================================================== */
int dfs_find_best_pattern(const int hand13[13], DFSResult *out)
{
    if (!hand13 || !out) return -1;
    memset(out, 0, sizeof(DFSResult));

    /* ── 0. 特殊牌型检测 ───────────────────────────────────────── */
    HandResult hr_sp = search_pattern(3, hand13, 13);
    if (hr_sp.position == 3 && hr_sp.score > 0) {
        out->is_special    = 1;
        out->special_score = hr_sp.score;
        out->special_name  = hr_sp.hand_name;
        out->typed_score   = hr_sp.score;
        return 0;
    }

    /* ── 1. 初始化上下文 ────────────────────────────────────────── */
    DFSContext *ctx = (DFSContext*)malloc(sizeof(DFSContext));
    if (!ctx) return -2;
    memset(ctx, 0, sizeof(DFSContext));
    ctx->hand13      = hand13;
    ctx->best_total  = -1;
    for (int i = 0; i < MEMO_SIZE; ++i) ctx->memo_score[i] = (int16_t)INVALID_SCORE;

    /* ── 2. 构建候选池 ──────────────────────────────────────────── */
    int chosen[5];
    enum_comb(hand13, 0,0,5, 2, chosen, ctx->tail_cands, &ctx->tail_cnt, MAX_TAIL_CANDS);
    enum_comb(hand13, 0,0,5, 1, chosen, ctx->mid_cands,  &ctx->mid_cnt,  MAX_MID_CANDS);
    qsort(ctx->tail_cands, (size_t)ctx->tail_cnt, sizeof(HandCand), cand_desc_cmp);
    qsort(ctx->mid_cands,  (size_t)ctx->mid_cnt,  sizeof(HandCand), cand_desc_cmp);

    /* ── 3. DFS 搜索 ────────────────────────────────────────────── */
    dfs_tail(ctx);

    /* ── 4. 从最优 mask 还原三墩 ──────────────────────────────────
     *
     *  设计原则：
     *    DFS 确定的是"哪些牌进有牌型墩"以及墩位强度约束。
     *    散牌分配（哪几张单牌填哪个散牌墩）不在此决策。
     *
     *  输出结构：
     *    typed_piles[]  —— 有牌型的墩（rank_order > 1），position已锁定
     *    loose_cards[]  —— 剩余散牌，按点数降序，由上层策略层分配
     *    occupied_positions —— 已被有牌型墩占用的墩位掩码
     *
     *  散牌约束（规则保证）：
     *    - 至少1个墩有牌型（typed_count >= 1）
     *    - 最多10张散牌（尾三条3张锁定 + 中5散 + 头3散）
     *    - 散牌张数 = 13 - sum(typed_piles[i].card_count)
     * ──────────────────────────────────────────────────────────── */

    uint16_t tail_mask = ctx->best_tail_mask;
    uint16_t mid_mask  = ctx->best_mid_mask;
    uint16_t head_mask = (uint16_t)(ALL_13_MASK ^ tail_mask ^ mid_mask);

    /* 评估三墩牌型 */
    int tail_cards[5], mid_cards[5], head_cards[3];
    mask_to_cards(hand13, tail_mask, tail_cards);
    mask_to_cards(hand13, mid_mask,  mid_cards);
    mask_to_cards(hand13, head_mask, head_cards);

    HandResult hr_tail = search_pattern(2, tail_cards, 5);
    HandResult hr_mid  = search_pattern(1, mid_cards,  5);
    HandResult hr_head = search_pattern(0, head_cards, 3);

    /* ── 5. 分类输出：有牌型墩 vs 散牌 ──────────────────────────── */
    out->typed_count        = 0;
    out->occupied_positions = 0;
    out->loose_count        = 0;
    out->typed_score        = 0;

    /* 尾墩 */
    if (hr_tail.rank_order > 1) {
        int idx = out->typed_count++;
        out->typed_piles[idx].position   = 2;
        out->typed_piles[idx].card_count = 5;
        memcpy(out->typed_piles[idx].cards, tail_cards, 5 * sizeof(int));
        out->typed_piles[idx].result     = hr_tail;
        out->occupied_positions          |= (1 << 2);
        out->typed_score                 += hr_tail.score;
    } else {
        /* 散牌：暂存，后面统一收集 */
    }

    /* 中墩 */
    if (hr_mid.rank_order > 1) {
        int idx = out->typed_count++;
        out->typed_piles[idx].position   = 1;
        out->typed_piles[idx].card_count = 5;
        memcpy(out->typed_piles[idx].cards, mid_cards, 5 * sizeof(int));
        out->typed_piles[idx].result     = hr_mid;
        out->occupied_positions          |= (1 << 1);
        out->typed_score                 += hr_mid.score;
    }

    /* 头墩 */
    if (hr_head.rank_order > 1) {
        int idx = out->typed_count++;
        out->typed_piles[idx].position   = 0;
        out->typed_piles[idx].card_count = 3;
        memcpy(out->typed_piles[idx].cards, head_cards, 3 * sizeof(int));
        out->typed_piles[idx].result     = hr_head;
        out->occupied_positions          |= (1 << 0);
        out->typed_score                 += hr_head.score;
    }

    /* ── 6. 收集散牌，按点数降序排列 ─────────────────────────────
     *
     *  散牌收集逻辑：
     *    遍历三个墩位中所有 rank_order <= 1 的墩，将其牌加入 loose_cards。
     *    上层知道 occupied_positions，可以推断出每个空墩需要几张牌：
     *      墩位0（头）需要3张，墩位1（中）需要5张，墩位2（尾）需要5张。
     *    loose_cards 总张数 = 13 - typed_piles 总牌数，上层按需取用即可。
     * ──────────────────────────────────────────────────────────── */
    if (!(out->occupied_positions & (1 << 2))) {
        for (int i = 0; i < 5; ++i)
            out->loose_cards[out->loose_count++] = tail_cards[i];
    }
    if (!(out->occupied_positions & (1 << 1))) {
        for (int i = 0; i < 5; ++i)
            out->loose_cards[out->loose_count++] = mid_cards[i];
    }
    if (!(out->occupied_positions & (1 << 0))) {
        for (int i = 0; i < 3; ++i)
            out->loose_cards[out->loose_count++] = head_cards[i];
    }

    /* 散牌按点数降序排列，方便上层按"保尾/保头/均衡"策略直接切片 */
    qsort(out->loose_cards, (size_t)out->loose_count, sizeof(int), int_desc_cmp);

    free(ctx);
    return 0;
}
