/*=====================================================================
 *  src/cpp/pattern/searchPattern.cpp
 *  ---------------------------------------------------------------
 *  实现：根据手牌判断墩位的牌型并返回对应的 HandTableEntry
 *  只使用 C 标准库，遵循 TODO.md 中的 “禁止 STL、禁止 new/delete” 约束
 *====================================================================*/

#include "pattern.h"
#include "cards.h"
#include "score.h"

#include <stddef.h>   // size_t
#include <stdbool.h>  // bool
#include <stdlib.h>   // qsort
#include <string.h>   // memset

/*--------------------------------------------------------------------
 *  辅助：升序 qsort 回调（仅对 int 数组排序）
 *--------------------------------------------------------------------*/
static int int_cmp(const void *a, const void *b)
{
    int ia = *(const int *)a;
    int ib = *(const int *)b;
    return (ia > ib) - (ia < ib);
}

/*--------------------------------------------------------------------
 *  统计点数频次（0~12）和花色频次（0~3）
 *--------------------------------------------------------------------*/
typedef struct {
    int rank_cnt[13];
    int suit_cnt[4];
    int sorted_ids[13];   // 仅在需要时使用，长度取决于实际牌数
    int cnt;              // 实际牌数
} CardStat;

/* 只使用固定大小数组，无动态分配 */
static void analyse_cards(const int *cards, int n, CardStat *st)
{
    memset(st, 0, sizeof(CardStat));
    st->cnt = n;

    for (int i = 0; i < n; ++i) {
        int id   = cards[i];
        int rank = card_rank(id);
        int suit = card_suit(id);
        st->rank_cnt[rank] ++;
        st->suit_cnt[suit] ++;
        st->sorted_ids[i] = id;
    }
    qsort(st->sorted_ids, (size_t)n, sizeof(int), int_cmp);
}

/*--------------------------------------------------------------------
 *  通用判定函数（返回 true 表示匹配）
 *--------------------------------------------------------------------*/
static bool is_three_of_a_kind(const CardStat *st)
{
    for (int i = 0; i < 13; ++i)
        if (st->rank_cnt[i] == 3) return true;
    return false;
}

static bool is_pair(const CardStat *st)
{
    for (int i = 0; i < 13; ++i)
        if (st->rank_cnt[i] == 2) return true;
    return false;
}

/* 两对：恰好出现两种点数各出现两次 */
static bool is_two_pair(const CardStat *st)
{
    int pair_cnt = 0;
    for (int i = 0; i < 13; ++i)
        if (st->rank_cnt[i] == 2) ++pair_cnt;
    return pair_cnt == 2;
}

/* 顺子：五张或三张连续（A 可作最高或最低） */
static bool is_straight(const CardStat *st, int n)
{
    /* 只在 n==3 或 n==5 时调用 */
    int ranks[13];
    int rcnt = 0;
    for (int i = 0; i < 13; ++i)
        if (st->rank_cnt[i]) ranks[rcnt++] = i;   // 只保留出现过的点数

    if (rcnt != n) return false;                 // 需要全部不同

    /* 检查普通递增 */
    bool ok = true;
    for (int i = 1; i < n; ++i)
        if (ranks[i] != ranks[i-1] + 1) { ok = false; break; }

    if (ok) return true;

    /* 处理 A-2-3-... 的环形顺子（仅在 5 张时出现 A2345） */
    if (n == 5 && ranks[0] == 0 && ranks[1] == 1 && ranks[2] == 2 &&
        ranks[3] == 3 && ranks[4] == 12)   // 12 == A
        return true;

    return false;
}

/* 同花 */
static bool is_flush(const CardStat *st)
{
    for (int i = 0; i < 4; ++i)
        if (st->suit_cnt[i] == st->cnt) return true;
    return false;
}

/* 葫芦：三条 + 一对 */
static bool is_full_house(const CardStat *st)
{
    bool three = false, pair = false;
    for (int i = 0; i < 13; ++i) {
        if (st->rank_cnt[i] == 3) three = true;
        if (st->rank_cnt[i] == 2) pair  = true;
    }
    return three && pair;
}

/* 四条 */
static bool is_four_of_a_kind(const CardStat *st)
{
    for (int i = 0; i < 13; ++i)
        if (st->rank_cnt[i] == 4) return true;
    return false;
}

/* 同花顺 */
static bool is_straight_flush(const CardStat *st, int n)
{
    return is_straight(st, n) && is_flush(st);
}

/* 五同（仅在双副牌且 5 张时） */
static bool is_five_of_a_kind(const CardStat *st)
{
    for (int i = 0; i < 13; ++i)
        if (st->rank_cnt[i] == 5) return true;
    return false;
}

/*--------------------------------------------------------------------
 *  特殊牌型（13 张）单独的判定函数（由大到小依次判定）
 *--------------------------------------------------------------------*/

/* 13. 至尊清龙 – 同花顺 + 点数全 2~A */
static bool is_royal_straight_flush_13(const CardStat *st) {
    for (int s = 0; s < 4; ++s) {
        if (st->suit_cnt[s] == 13) {
            for (int i = 0; i < 13; ++i) {
                if (st->rank_cnt[i] != 1) return false;
            }
            return true;
        }
    }
    return false;
}

/* 12. 一条龙 – 13 张点数全不重复且覆盖 2~A */
static bool is_straight_13(const CardStat *st) {
    for (int i = 0; i < 13; ++i) {
        if (st->rank_cnt[i] != 1) return false;
    }
    return true;
}

/* 11. 十二皇族 – 12 张 J/Q/K/A */
static bool is_twelve_royals(const CardStat *st) {
    int cnt = 0;
    for (int i = 9; i < 13; ++i) {
        cnt += st->rank_cnt[i];
    }
    return cnt == 12;
}

/* 辅助：三同花顺 DFS 探索（包含 5, 5, 3 张组合） */
static bool dfs_three_sf(int suit_ranks[4][13], int target_lengths[], int target_idx) {
    if (target_idx == 3) {
        for (int s = 0; s < 4; ++s)
            for (int i = 0; i < 13; ++i)
                if (suit_ranks[s][i] != 0) return false;
        return true;
    }
    int len = target_lengths[target_idx];
    for (int s = 0; s < 4; ++s) {
        for (int i = 0; i <= 13 - len; ++i) {
            bool ok = true;
            for (int j = 0; j < len; ++j) {
                if (suit_ranks[s][i+j] == 0) { ok = false; break; }
            }
            if (ok) {
                for (int j = 0; j < len; ++j) suit_ranks[s][i+j]--;
                if (dfs_three_sf(suit_ranks, target_lengths, target_idx + 1)) return true;
                for (int j = 0; j < len; ++j) suit_ranks[s][i+j]++;
            }
        }
        if (len == 5 && suit_ranks[s][12] > 0 && suit_ranks[s][0] > 0 && suit_ranks[s][1] > 0 && suit_ranks[s][2] > 0 && suit_ranks[s][3] > 0) {
            suit_ranks[s][12]--; suit_ranks[s][0]--; suit_ranks[s][1]--; suit_ranks[s][2]--; suit_ranks[s][3]--;
            if (dfs_three_sf(suit_ranks, target_lengths, target_idx + 1)) return true;
            suit_ranks[s][12]++; suit_ranks[s][0]++; suit_ranks[s][1]++; suit_ranks[s][2]++; suit_ranks[s][3]++;
        }
        if (len == 3 && suit_ranks[s][12] > 0 && suit_ranks[s][0] > 0 && suit_ranks[s][1] > 0) {
            suit_ranks[s][12]--; suit_ranks[s][0]--; suit_ranks[s][1]--;
            if (dfs_three_sf(suit_ranks, target_lengths, target_idx + 1)) return true;
            suit_ranks[s][12]++; suit_ranks[s][0]++; suit_ranks[s][1]++;
        }
    }
    return false;
}

/* 10. 三同花顺 – 三个同花顺 (墩位分部为3张/5张/5张) */
static bool is_three_straight_flush(const int *cards) {
    int suit_ranks[4][13] = {0};
    for (int i = 0; i < 13; ++i) {
        suit_ranks[card_suit(cards[i])][card_rank(cards[i])]++;
    }
    int target[3] = {5, 5, 3};
    return dfs_three_sf(suit_ranks, target, 0);
}

/* 9. 三分天下 – 三个四条 */
static bool is_three_four_of_a_kind(const CardStat *st) {
    int four_cnt = 0;
    for (int i = 0; i < 13; ++i) {
        if (st->rank_cnt[i] == 4) four_cnt++;
    }
    return four_cnt == 3;
}

/* 8. 全大 – 点数全部在 8~A (rank 6~12) */
static bool is_all_big(const CardStat *st) {
    for (int i = 0; i < 6; ++i) {
        if (st->rank_cnt[i] > 0) return false;
    }
    return true;
}

/* 7. 全小 – 点数全部在 2~8 (rank 0~6) */
static bool is_all_small(const CardStat *st) {
    for (int i = 7; i < 13; ++i) {
        if (st->rank_cnt[i] > 0) return false;
    }
    return true;
}

/* 6. 同色 – 全部同花色（黑或红） */
static bool is_same_color(const CardStat *st) {
    // 0:D(红), 1:C(黑), 2:H(红), 3:S(黑)
    int red = st->suit_cnt[0] + st->suit_cnt[2];
    int black = st->suit_cnt[1] + st->suit_cnt[3];
    return red == 13 || black == 13;
}

/* 5. 四套三条 – 4×三条 */
static bool is_four_three_of_a_kind(const CardStat *st) {
    int three_cnt = 0;
    for (int i = 0; i < 13; ++i) {
        if (st->rank_cnt[i] == 3) three_cnt++;
    }
    return three_cnt == 4;
}

/* 4. 五对三条 – 5 对 + 1 三条 */
static bool is_five_pair_three(const CardStat *st) {
    int pair_cnt = 0, three_cnt = 0;
    for (int i = 0; i < 13; ++i) {
        if (st->rank_cnt[i] == 2) pair_cnt++;
        else if (st->rank_cnt[i] == 3) three_cnt++;
    }
    return pair_cnt == 5 && three_cnt == 1;
}

/* 3. 六对半 – 6 对 + 1 单 */
static bool is_six_and_half_pair(const CardStat *st) {
    int pair_cnt = 0, single_cnt = 0;
    for (int i = 0; i < 13; ++i) {
        if (st->rank_cnt[i] == 2) pair_cnt++;
        else if (st->rank_cnt[i] == 1) single_cnt++;
    }
    return pair_cnt == 6 && single_cnt == 1;
}

/* 2. 三同花 – 分布为3张/5张/5张的三个同花（不要求顺子） */
static bool is_three_flush(const CardStat *st) {
    for (int i = 0; i < 4; ++i) {
        int c = st->suit_cnt[i];
        // 如果数量不能被3或5拆分覆盖，就不符合三同花的组合要求
        if (c != 0 && c != 3 && c != 5 && c != 8 && c != 10 && c != 13) {
            return false;
        }
    }
    return true;
}

/* 辅助：三顺子 DFS 探索（包含 5, 5, 3 张组合） */
static bool dfs_three_straights(int *ranks, int target_lengths[], int target_idx) {
    if (target_idx == 3) {
        for (int i = 0; i < 13; ++i) if (ranks[i] != 0) return false;
        return true;
    }
    int len = target_lengths[target_idx];
    for (int i = 0; i <= 13 - len; ++i) {
        bool ok = true;
        for (int j = 0; j < len; ++j) {
            if (ranks[i+j] == 0) { ok = false; break; }
        }
        if (ok) {
            for (int j = 0; j < len; ++j) ranks[i+j]--;
            if (dfs_three_straights(ranks, target_lengths, target_idx + 1)) return true;
            for (int j = 0; j < len; ++j) ranks[i+j]++;
        }
    }
    if (len == 5 && ranks[12] > 0 && ranks[0] > 0 && ranks[1] > 0 && ranks[2] > 0 && ranks[3] > 0) {
        ranks[12]--; ranks[0]--; ranks[1]--; ranks[2]--; ranks[3]--;
        if (dfs_three_straights(ranks, target_lengths, target_idx + 1)) return true;
        ranks[12]++; ranks[0]++; ranks[1]++; ranks[2]++; ranks[3]++;
    }
    if (len == 3 && ranks[12] > 0 && ranks[0] > 0 && ranks[1] > 0) {
        ranks[12]--; ranks[0]--; ranks[1]--;
        if (dfs_three_straights(ranks, target_lengths, target_idx + 1)) return true;
        ranks[12]++; ranks[0]++; ranks[1]++;
    }
    return false;
}

/* 1. 三顺子 – 三个独立的顺子 (墩位分布为3张/5张/5张) */
static bool is_three_straight(const CardStat *st) {
    int ranks[13];
    for (int i = 0; i < 13; ++i) ranks[i] = st->rank_cnt[i];
    int target[3] = {5, 5, 3};
    return dfs_three_straights(ranks, target, 0);
}

/*--------------------------------------------------------------------
 *  特殊牌型入口（按牌型从大到小依次判断）
 *--------------------------------------------------------------------*/
static const thirteencards::HandTableEntry* check_special(const int *cards)
{
    using namespace thirteencards;
    CardStat st;
    analyse_cards(cards, 13, &st);

    const char *found_name = nullptr;

    if (is_royal_straight_flush_13(&st))          found_name = "Royal Straight Flush 13";
    else if (is_straight_13(&st))                 found_name = "Straight 13";
    else if (is_twelve_royals(&st))               found_name = "Twelve Royals";
    else if (is_three_straight_flush(cards))      found_name = "Three Straight Flush";
    else if (is_three_four_of_a_kind(&st))        found_name = "Three Four of a Kind";
    else if (is_all_big(&st))                     found_name = "All Big";
    else if (is_all_small(&st))                   found_name = "All Small";
    else if (is_same_color(&st))                  found_name = "Same Color";
    else if (is_four_three_of_a_kind(&st))        found_name = "Four Three of a Kind";
    else if (is_five_pair_three(&st))             found_name = "Five Pair Three";
    else if (is_six_and_half_pair(&st))           found_name = "Six and Half Pair";
    else if (is_three_flush(&st))                 found_name = "Three Flush";
    else if (is_three_straight(&st))              found_name = "Three Straight";

    if (found_name) {
        for (int i = 0; i < SPECIAL_HANDS_COUNT; ++i) {
            if (SPECIAL_HANDS[i].hand_name && strcmp(SPECIAL_HANDS[i].hand_name, found_name) == 0) {
                return &SPECIAL_HANDS[i];
            }
        }
    }

    return nullptr;
}

/*--------------------------------------------------------------------
 *  根据 position 返回对应的 HandTableEntry（普通或特殊）
 *--------------------------------------------------------------------*/
extern "C"
{
    static HandResult make_unknown(int pos)
    {
        HandResult r;
        r.position   = pos;
        r.hand_name  = "Unknown";
        r.rank_order = 0;
        r.score      = 0;
        return r;
    }

    /* --------------------------------------------------------------
     *  主函数：search_pattern
     *
     *  参数:
     *      position   – 0=head, 1=middle, 2=tail, 3=special
     *      cards      – 牌号数组（长度由 position 决定）
     *      cnt        – 实际牌数（3、5、13）
     *
     *  返回:
     *      HandResult 结构体（拷贝），其中 hand_name、rank_order、score
     *      来自对应的 HandTableEntry；若未匹配返回 "Unknown".
     * --------------------------------------------------------------*/
    HandResult search_pattern(int position, const int *cards, int cnt)
    {
        using namespace thirteencards;

        CardStat st;
        analyse_cards(cards, cnt, &st);

        /* ---------- 特殊牌型（13 张） ---------- */
        if (position == 3 && cnt == 13) {
            const HandTableEntry *sp = check_special(cards);
            if (sp) {
                HandResult r = { sp->position, sp->hand_name,
                                sp->rank_order, sp->score };
                return r;
            }
            return make_unknown(position);
        }

        /* ---------- 普通牌型 ---------- */
        const HandTableEntry *table = nullptr;

        /* 1) 头墩（3 张） */
        if (position == 0 && cnt == 3) {
            if (is_three_of_a_kind(&st)) {
                for (int i = 0; i < REGULAR_HANDS_COUNT; ++i)
                    if (REGULAR_HANDS[i].position == POS_HEAD &&
                        strcmp(REGULAR_HANDS[i].hand_name,
                               "Three of a Kind") == 0) {
                        table = &REGULAR_HANDS[i];
                        break;
                    }
            } else if (is_pair(&st)) {
                for (int i = 0; i < REGULAR_HANDS_COUNT; ++i)
                    if (REGULAR_HANDS[i].position == POS_HEAD &&
                        strcmp(REGULAR_HANDS[i].hand_name,
                               "Pair") == 0) {
                        table = &REGULAR_HANDS[i];
                        break;
                    }
            } else {
                for (int i = 0; i < REGULAR_HANDS_COUNT; ++i)
                    if (REGULAR_HANDS[i].position == POS_HEAD &&
                        strcmp(REGULAR_HANDS[i].hand_name,
                               "High Card") == 0) {
                        table = &REGULAR_HANDS[i];
                        break;
                    }
            }
        }

        /* 2) 中、底墩（5 张） */
        else if ((position == 1 || position == 2) && cnt == 5) {
            /* 检查从最高级到最低级的顺序 */
            if (is_five_of_a_kind(&st)) {
                /* 五同只在双副牌时出现，直接使用 MULTI_DECK_HANDS */
                const HandTableEntry *src = nullptr;
                for (int i = 0; i < MULTI_DECK_HANDS_COUNT; ++i)
                    if (MULTI_DECK_HANDS[i].position ==
                        (position == 1 ? POS_MIDDLE : POS_TAIL) &&
                        strcmp(MULTI_DECK_HANDS[i].hand_name,
                               "Five of a Kind") == 0) {
                        src = &MULTI_DECK_HANDS[i];
                        break;
                    }
                if (src) table = src;
            }
            if (!table && is_straight_flush(&st, 5)) {
                for (int i = 0; i < REGULAR_HANDS_COUNT; ++i)
                    if (REGULAR_HANDS[i].position ==
                        (position == 1 ? POS_MIDDLE : POS_TAIL) &&
                        strcmp(REGULAR_HANDS[i].hand_name,
                               "Straight Flush") == 0) {
                        table = &REGULAR_HANDS[i];
                        break;
                    }
            }
            if (!table && is_four_of_a_kind(&st)) {
                for (int i = 0; i < REGULAR_HANDS_COUNT; ++i)
                    if (REGULAR_HANDS[i].position ==
                        (position == 1 ? POS_MIDDLE : POS_TAIL) &&
                        strcmp(REGULAR_HANDS[i].hand_name,
                               "Four of a Kind") == 0) {
                        table = &REGULAR_HANDS[i];
                        break;
                    }
            }
            if (!table && is_full_house(&st)) {
                for (int i = 0; i < REGULAR_HANDS_COUNT; ++i)
                    if (REGULAR_HANDS[i].position ==
                        (position == 1 ? POS_MIDDLE : POS_TAIL) &&
                        strcmp(REGULAR_HANDS[i].hand_name,
                               "Full House") == 0) {
                        table = &REGULAR_HANDS[i];
                        break;
                    }
            }
            if (!table && is_flush(&st)) {
                for (int i = 0; i < REGULAR_HANDS_COUNT; ++i)
                    if (REGULAR_HANDS[i].position ==
                        (position == 1 ? POS_MIDDLE : POS_TAIL) &&
                        strcmp(REGULAR_HANDS[i].hand_name,
                               "Flush") == 0) {
                        table = &REGULAR_HANDS[i];
                        break;
                    }
            }
            if (!table && is_straight(&st, 5)) {
                for (int i = 0; i < REGULAR_HANDS_COUNT; ++i)
                    if (REGULAR_HANDS[i].position ==
                        (position == 1 ? POS_MIDDLE : POS_TAIL) &&
                        strcmp(REGULAR_HANDS[i].hand_name,
                               "Straight") == 0) {
                        table = &REGULAR_HANDS[i];
                        break;
                    }
            }
            if (!table && is_three_of_a_kind(&st)) {
                for (int i = 0; i < REGULAR_HANDS_COUNT; ++i)
                    if (REGULAR_HANDS[i].position ==
                        (position == 1 ? POS_MIDDLE : POS_TAIL) &&
                        strcmp(REGULAR_HANDS[i].hand_name,
                               "Three of a Kind") == 0) {
                        table = &REGULAR_HANDS[i];
                        break;
                    }
            }
            if (!table && is_two_pair(&st)) {
                for (int i = 0; i < REGULAR_HANDS_COUNT; ++i)
                    if (REGULAR_HANDS[i].position ==
                        (position == 1 ? POS_MIDDLE : POS_TAIL) &&
                        strcmp(REGULAR_HANDS[i].hand_name,
                               "Two Pair") == 0) {
                        table = &REGULAR_HANDS[i];
                        break;
                    }
            }
            if (!table && is_pair(&st)) {
                for (int i = 0; i < REGULAR_HANDS_COUNT; ++i)
                    if (REGULAR_HANDS[i].position ==
                        (position == 1 ? POS_MIDDLE : POS_TAIL) &&
                        strcmp(REGULAR_HANDS[i].hand_name,
                               "One Pair") == 0) {
                        table = &REGULAR_HANDS[i];
                        break;
                    }
            }
            if (!table) {
                for (int i = 0; i < REGULAR_HANDS_COUNT; ++i)
                    if (REGULAR_HANDS[i].position ==
                        (position == 1 ? POS_MIDDLE : POS_TAIL) &&
                        strcmp(REGULAR_HANDS[i].hand_name,
                               "High Card") == 0) {
                        table = &REGULAR_HANDS[i];
                        break;
                    }
            }
        }

        if (table) {
            HandResult r = { table->position,
                             table->hand_name,
                             table->rank_order,
                             table->score };
            return r;
        }

        /* 未匹配到任何已知牌型 */
        return make_unknown(position);
    }
}   /* extern "C" */

/*=====================================================================
 *  新增模块：13张手牌的常规牌型全量包含判定 (独立模块)
 *  ---------------------------------------------------------------
 *  用途：扫描 13 张手牌，分析并标记其中“包含”的所有可用基础常规牌型。
 *  约束：严格遵循禁止 STL、禁止 new/delete 的纯 C 风格实现。
 *====================================================================*/

extern "C"
{
    /* 描述 13 张牌中包含的常规牌型状态的结构体 */
    typedef struct {
        /* 精确数量统计 (用于快速判断能拆出多少组) */
        int exact_pairs;     // 仅出现 2 次的点数个数
        int exact_threes;    // 仅出现 3 次的点数个数
        int exact_fours;     // 仅出现 4 次的点数个数 (铁支)
        int exact_fives;     // 仅出现 5 次的点数个数 (五同，仅多副牌可能)

        /* 组合牌型存在性判断 (布尔值: 1表示存在, 0表示不存在) */
        int has_pair;           // 是否至少包含一个对子
        int has_two_pair;       // 是否至少包含两对
        int has_three_kind;     // 是否至少包含一个三条
        int has_straight;       // 是否至少包含一个顺子
        int has_flush;          // 是否至少包含一个同花
        int has_full_house;     // 是否至少包含一个葫芦
        int has_four_kind;      // 是否至少包含一个铁支 (同 exact_fours > 0)
        int has_straight_flush; // 是否至少包含一个同花顺
        int has_five_kind;      // 是否至少包含一个五同 (同 exact_fives > 0)

        /* 详细阵列信息 (可选，供进一步提牌使用) */
        int flush_suits[4];         // 记录四种花色各自拥有的牌数 (>=5即可组成同花)
        int straight_starts[13];    // 记录可作为顺子起点的点数 (1表示可作为顺子起点)
    } ThirteenCardsRegularStatus;

    /*
     * 函数名：analyze_13cards_regular_patterns
     * 功能：传入 13 张牌的数组，输出其中包含的所有常规牌型的统计信息
     * 参数：
     *   cards - 大小为 13 的整型数组，表示卡牌ID
     *   out_status - 指向外部申请好的结构体，用于接收分析结果
     */
    void analyze_13cards_regular_patterns(const int *cards, ThirteenCardsRegularStatus *out_status)
    {
        if (!cards || !out_status) return;
        memset(out_status, 0, sizeof(ThirteenCardsRegularStatus));

        int rank_cnt[13] = {0};
        int suit_cnt[4]  = {0};
        int suit_ranks[4][13] = {0}; // 记录每种花色中各个点数的存在情况，用于判断同花顺

        // 1. 遍历 13 张牌，收集基础频次统计
        for (int i = 0; i < 13; ++i) {
            int id = cards[i];
            int r  = card_rank(id); // 0=2, 1=3, ..., 12=A
            int s  = card_suit(id); // 0~3

            rank_cnt[r]++;
            suit_cnt[s]++;
            suit_ranks[s][r]++;
        }

        // 2. 统计对子、三条、四条、五同数量
        for (int i = 0; i < 13; ++i) {
            if (rank_cnt[i] == 5) out_status->exact_fives++;
            else if (rank_cnt[i] == 4) out_status->exact_fours++;
            else if (rank_cnt[i] == 3) out_status->exact_threes++;
            else if (rank_cnt[i] == 2) out_status->exact_pairs++;
        }

        // 3. 判定对子、三条、铁支、五同的包含关系
        out_status->has_five_kind  = (out_status->exact_fives > 0) ? 1 : 0;
        out_status->has_four_kind  = (out_status->exact_fours > 0) ? 1 : 0;
        out_status->has_three_kind = (out_status->exact_threes > 0 || out_status->exact_fours > 0 || out_status->exact_fives > 0) ? 1 : 0;
        out_status->has_pair       = (out_status->exact_pairs > 0 || out_status->has_three_kind) ? 1 : 0;

        // 4. 判定两对 (Two Pair)
        // 形成两对的条件：有两组以上的对子(或三条等)，或者有一个铁支/五同可以拆成两对
        if (out_status->exact_fives >= 1 || out_status->exact_fours >= 1) {
            out_status->has_two_pair = 1; // 铁支或五同可拆为两对
        } else {
            int total_groups = out_status->exact_pairs + out_status->exact_threes;
            if (total_groups >= 2) out_status->has_two_pair = 1;
        }

        // 5. 判定葫芦 (Full House)
        // 形成葫芦的条件：三条+对子，或者两个三条，或者铁支+对子/三条，或者五同拆分为三条+对子
        if (out_status->exact_fives >= 1) {
            out_status->has_full_house = 1; // AAA+AA
        } else if (out_status->exact_fours >= 1 && (out_status->exact_pairs >= 1 || out_status->exact_threes >= 1)) {
            out_status->has_full_house = 1;
        } else if (out_status->exact_threes >= 2) {
            out_status->has_full_house = 1; // 两个三条可以抽出一个葫芦
        } else if (out_status->exact_threes >= 1 && out_status->exact_pairs >= 1) {
            out_status->has_full_house = 1;
        }

        // 6. 判定同花 (Flush)
        for (int i = 0; i < 4; ++i) {
            out_status->flush_suits[i] = suit_cnt[i];
            if (suit_cnt[i] >= 5) {
                out_status->has_flush = 1;
            }
        }

        // 7. 判定顺子 (Straight)
        // 遍历所有可能的起始点 0(2) 到 8(10)
        for (int i = 0; i <= 8; ++i) {
            if (rank_cnt[i] > 0 && rank_cnt[i+1] > 0 && rank_cnt[i+2] > 0 &&
                rank_cnt[i+3] > 0 && rank_cnt[i+4] > 0) {
                out_status->has_straight = 1;
                out_status->straight_starts[i] = 1;
            }
        }
        // 特殊顺子：A-2-3-4-5 (12(A) 和 0,1,2,3)
        if (rank_cnt[12] > 0 && rank_cnt[0] > 0 && rank_cnt[1] > 0 &&
            rank_cnt[2] > 0 && rank_cnt[3] > 0) {
            out_status->has_straight = 1;
            out_status->straight_starts[12] = 1; // 用 12 表示 A2345 起点
        }

        // 8. 判定同花顺 (Straight Flush)
        // 在满足同花的 suit 中寻找顺子
        for (int s = 0; s < 4; ++s) {
            if (suit_cnt[s] < 5) continue;

            // 常规同花顺
            for (int i = 0; i <= 8; ++i) {
                if (suit_ranks[s][i] > 0 && suit_ranks[s][i+1] > 0 && suit_ranks[s][i+2] > 0 &&
                    suit_ranks[s][i+3] > 0 && suit_ranks[s][i+4] > 0) {
                    out_status->has_straight_flush = 1;
                    break;
                }
            }
            // A-2-3-4-5 同花顺
            if (!out_status->has_straight_flush) {
                if (suit_ranks[s][12] > 0 && suit_ranks[s][0] > 0 && suit_ranks[s][1] > 0 &&
                    suit_ranks[s][2] > 0 && suit_ranks[s][3] > 0) {
                    out_status->has_straight_flush = 1;
                }
            }
        }
    }
} /* extern "C" */
