#include "round.h"
#include "players/player.h"
#include "cards/cards.h"
#include <cstdio>
#include <cstdlib>

namespace {

struct PairSettleResult {
    int winner;      // 1: a胜, -1: b胜, 0: 平
    int base_score;  // 基础输赢分（未乘倍率）
    bool shoot_a;    // a 是否打枪（赢3墩）
    bool shoot_b;    // b 是否打枪（赢3墩）
};

static int compare_hand_result(const HandResult& a, const HandResult& b)
{
    if (a.rank_order > b.rank_order) return 1;
    if (a.rank_order < b.rank_order) return -1;
    return 0;
}

static void build_rank_count(const int* cards, int cnt, int freq[13])
{
    for (int i = 0; i < 13; ++i) freq[i] = 0;
    for (int i = 0; i < cnt; ++i) {
        int r = card_rank(cards[i]) % 13;
        if (r < 0) r += 13;
        ++freq[r];
    }
}

static int straight_high_rank(const int freq[13])
{
    // A2345 顺子（轮子）
    if (freq[12] && freq[0] && freq[1] && freq[2] && freq[3]) return 3;
    for (int hi = 12; hi >= 4; --hi) {
        if (freq[hi] && freq[hi - 1] && freq[hi - 2] && freq[hi - 3] && freq[hi - 4]) return hi;
    }
    return -1;
}

static int compare_rank_tuple_desc(const int* a, const int* b, int n)
{
    for (int i = 0; i < n; ++i) {
        if (a[i] > b[i]) return 1;
        if (a[i] < b[i]) return -1;
    }
    return 0;
}

static int compare_head_3cards(const int* ca, const int* cb)
{
    int fa[13], fb[13];
    build_rank_count(ca, 3, fa);
    build_rank_count(cb, 3, fb);

    int tripa = -1, tripb = -1, paira = -1, pairb = -1;
    int kicka = -1, kickb = -1;
    int higha[3], highb[3], ia = 0, ib = 0;
    for (int r = 12; r >= 0; --r) {
        if (fa[r] == 3) tripa = r;
        else if (fa[r] == 2) paira = r;
        else if (fa[r] == 1) kicka = r;
        for (int k = 0; k < fa[r]; ++k) higha[ia++] = r;

        if (fb[r] == 3) tripb = r;
        else if (fb[r] == 2) pairb = r;
        else if (fb[r] == 1) kickb = r;
        for (int k = 0; k < fb[r]; ++k) highb[ib++] = r;
    }

    if (tripa >= 0 || tripb >= 0) {
        if (tripa > tripb) return 1;
        if (tripa < tripb) return -1;
        return 0;
    }
    if (paira >= 0 || pairb >= 0) {
        if (paira > pairb) return 1;
        if (paira < pairb) return -1;
        if (kicka > kickb) return 1;
        if (kicka < kickb) return -1;
        return 0;
    }
    return compare_rank_tuple_desc(higha, highb, 3);
}

static int compare_five_cards(const int* ca, const int* cb)
{
    int fa[13], fb[13];
    build_rank_count(ca, 5, fa);
    build_rank_count(cb, 5, fb);

    int foura = -1, fourb = -1, threea = -1, threeb = -1;
    int pairsa[2] = {-1, -1}, pairsb[2] = {-1, -1};
    int pa = 0, pb = 0;
    int kicka[5], kickb[5], ka = 0, kb = 0;

    for (int r = 12; r >= 0; --r) {
        if (fa[r] == 4) foura = r;
        else if (fa[r] == 3) threea = r;
        else if (fa[r] == 2 && pa < 2) pairsa[pa++] = r;
        else if (fa[r] == 1) kicka[ka++] = r;

        if (fb[r] == 4) fourb = r;
        else if (fb[r] == 3) threeb = r;
        else if (fb[r] == 2 && pb < 2) pairsb[pb++] = r;
        else if (fb[r] == 1) kickb[kb++] = r;
    }

    if (foura >= 0 || fourb >= 0) {
        if (foura > fourb) return 1;
        if (foura < fourb) return -1;
        if (kicka[0] > kickb[0]) return 1;
        if (kicka[0] < kickb[0]) return -1;
        return 0;
    }

    if (threea >= 0 && pa >= 1 && threeb >= 0 && pb >= 1) { // 葫芦
        if (threea > threeb) return 1;
        if (threea < threeb) return -1;
        if (pairsa[0] > pairsb[0]) return 1;
        if (pairsa[0] < pairsb[0]) return -1;
        return 0;
    }

    int sa = straight_high_rank(fa), sb = straight_high_rank(fb);
    if (sa >= 0 || sb >= 0) { // 顺子/同花顺都用最高张比较
        if (sa > sb) return 1;
        if (sa < sb) return -1;
        return 0;
    }

    if (threea >= 0 || threeb >= 0) { // 三条
        if (threea > threeb) return 1;
        if (threea < threeb) return -1;
        return compare_rank_tuple_desc(kicka, kickb, 2);
    }

    if (pa == 2 || pb == 2) { // 两对
        if (pairsa[0] > pairsb[0]) return 1;
        if (pairsa[0] < pairsb[0]) return -1;
        if (pairsa[1] > pairsb[1]) return 1;
        if (pairsa[1] < pairsb[1]) return -1;
        if (kicka[0] > kickb[0]) return 1;
        if (kicka[0] < kickb[0]) return -1;
        return 0;
    }

    if (pa == 1 || pb == 1) { // 一对
        if (pairsa[0] > pairsb[0]) return 1;
        if (pairsa[0] < pairsb[0]) return -1;
        return compare_rank_tuple_desc(kicka, kickb, 3);
    }

    return compare_rank_tuple_desc(kicka, kickb, 5); // 乌龙/同花
}

static int compare_same_rank_by_cards(int position, const int* ca, const int* cb)
{
    if (position == 0) return compare_head_3cards(ca, cb);
    return compare_five_cards(ca, cb);
}

static int compare_position(PlayerRound* a, PlayerRound* b, int pos)
{
    HandResult ha = {0, "Unknown", 0, 0};
    HandResult hb = {0, "Unknown", 0, 0};
    if (a->getPositionResult(pos, &ha) != 0) return 0;
    if (b->getPositionResult(pos, &hb) != 0) return 0;

    int cmp = compare_hand_result(ha, hb);
    if (cmp != 0) return cmp;

    int ca[5] = {0, 0, 0, 0, 0};
    int cb[5] = {0, 0, 0, 0, 0};
    if (a->getPositionCards(pos, ca) != 0) return 0;
    if (b->getPositionCards(pos, cb) != 0) return 0;
    return compare_same_rank_by_cards(pos, ca, cb);
}

static bool is_player_fouled(PlayerRound* p)
{
    if (!p) return false;
    if (p->isSpecialHand()) return false; // 特殊牌型不判倒水

    // 不倒水要求：尾 >= 中 >= 头
    HandResult h = {0, "Unknown", 0, 0};
    HandResult m = {0, "Unknown", 0, 0};
    HandResult t = {0, "Unknown", 0, 0};
    if (p->getPositionResult(0, &h) != 0) return true;
    if (p->getPositionResult(1, &m) != 0) return true;
    if (p->getPositionResult(2, &t) != 0) return true;

    return (compare_hand_result(t, m) < 0 ||
            compare_hand_result(m, h) < 0);
}

static PairSettleResult settle_pair(PlayerRound* a, PlayerRound* b)
{
    PairSettleResult r = {0, 0, false, false};
    if (!a || !b) return r;

    // 特殊牌型：直接按特殊牌型等级比较（不参与打枪）
    if (a->isSpecialHand() || b->isSpecialHand()) {
        HandResult sa = a->getSpecialResult();
        HandResult sb = b->getSpecialResult();
        if (!a->isSpecialHand()) {
            sa.rank_order = 0;
            sa.score = 0;
        }
        if (!b->isSpecialHand()) {
            sb.rank_order = 0;
            sb.score = 0;
        }
        int cmp = compare_hand_result(sa, sb);
        if (cmp > 0) {
            r.winner = 1;
            r.base_score = (sa.score > 0) ? sa.score : 0;
        } else if (cmp < 0) {
            r.winner = -1;
            r.base_score = (sb.score > 0) ? sb.score : 0;
        }
        return r;
    }

    int score_sum = 0;
    int win_a = 0, win_b = 0;
    for (int pos = 0; pos < 3; ++pos) {
        HandResult ha = {0, "Unknown", 0, 0};
        HandResult hb = {0, "Unknown", 0, 0};
        if (a->getPositionResult(pos, &ha) != 0) continue;
        if (b->getPositionResult(pos, &hb) != 0) continue;

        int cmp = compare_position(a, b, pos);
        if (cmp > 0) {
            score_sum += ha.score;
            ++win_a;
        } else if (cmp < 0) {
            score_sum -= hb.score;
            ++win_b;
        }
    }

    r.shoot_a = (win_a == 3);
    r.shoot_b = (win_b == 3);
    if (score_sum > 0) {
        r.winner = 1;
        r.base_score = score_sum;
    } else if (score_sum < 0) {
        r.winner = -1;
        r.base_score = -score_sum;
    }
    return r;
}

} // namespace

/*
 * round_close
 * ----------
 * 1. 逐玩家调用 settle()，得到本局得分。
 * 2. 两两比较得分，打印胜负信息（可自行改为计分/统计）。
 * 3. 检测特殊成就（全垒打、至尊清龙等），并在控制台提示。
 * 4. 调用 PlayerRound::resetRound() 清空局内部数据。
 * 5. 释放本局牌堆并复位 Round 结构体成员。
 *
 * 返回值:
 *   0  – 成功
 *  -1 – 参数为空
 *  -2 – 玩家数组为空
 *  -3 – 玩家数量非法
 */
int round_close(Round* r) {
    if (!r) return -1;                 // 参数为空
    if (!r->players) return -2;        // 玩家数组为空
    int n = r->player_cnt;
    if (n <= 0) return -3;            // 非法玩家数量

    // -------------------------------------------------
    // 1) 逐玩家完成牌型结算（确保三墩结果可读取）
    // -------------------------------------------------
    int* round_scores = (int*)malloc(sizeof(int) * n);
    int* net_scores = (int*)malloc(sizeof(int) * n);
    int* beat_cnt = (int*)malloc(sizeof(int) * n); // 用于判断全垒打
    bool* fouled = (bool*)malloc(sizeof(bool) * n);
    if (!round_scores || !net_scores || !beat_cnt || !fouled) {
        if (round_scores) free(round_scores);
        if (net_scores) free(net_scores);
        if (beat_cnt) free(beat_cnt);
        if (fouled) free(fouled);
        return -4;
    }

    for (int i = 0; i < n; ++i) {
        PlayerRound* pr = r->players[i];
        net_scores[i] = 0;
        beat_cnt[i] = 0;
        if (!pr) {
            round_scores[i] = 0;
            fouled[i] = false;
            continue;
        }
        int rc = pr->settle();
        round_scores[i] = (rc < 0) ? 0 : rc;
        fouled[i] = is_player_fouled(pr);
    }

    // -------------------------------------------------
    // 2) 两两比较，先得到基础结果并统计“击败人数”
    // -------------------------------------------------
    PairSettleResult* pair_results =
        (PairSettleResult*)malloc(sizeof(PairSettleResult) * n * n);
    if (!pair_results) {
        free(round_scores);
        free(net_scores);
        free(beat_cnt);
        free(fouled);
        return -4;
    }
    for (int i = 0; i < n * n; ++i) pair_results[i] = {0, 0, false, false};

    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            if (fouled[i] || fouled[j]) continue; // 倒水玩家不参与两两结算
            PairSettleResult pr = settle_pair(r->players[i], r->players[j]);
            pair_results[i * n + j] = pr;
            if (pr.winner == 1) ++beat_cnt[i];
            else if (pr.winner == -1) ++beat_cnt[j];
        }
    }

    // -------------------------------------------------
    // 3) 全垒打检测：击败所有其他玩家（倍率3，且不触发打枪）
    // -------------------------------------------------
    bool* homerun = (bool*)malloc(sizeof(bool) * n);
    if (!homerun) {
        free(pair_results);
        free(round_scores);
        free(net_scores);
        free(beat_cnt);
        free(fouled);
        return -4;
    }
    for (int i = 0; i < n; ++i) {
        if (fouled[i]) {
            homerun[i] = false;
            continue;
        }
        int opponents = 0;
        for (int j = 0; j < n; ++j) {
            if (j == i || fouled[j]) continue;
            ++opponents;
        }
        homerun[i] = (opponents > 0 && beat_cnt[i] == opponents);
    }

    // -------------------------------------------------
    // 4) 计算最终两两输赢：全垒打x3 > 打枪x2 > 基础分
    // -------------------------------------------------
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            if (fouled[i] || fouled[j]) continue;
            PairSettleResult pr = pair_results[i * n + j];
            if (pr.winner == 0 || pr.base_score <= 0) continue;

            int final_score = pr.base_score;
            if (pr.winner == 1) {
                if (homerun[i]) final_score *= 3;
                else if (pr.shoot_a) final_score *= 2;
                net_scores[i] += final_score;
                net_scores[j] -= final_score;
            } else {
                if (homerun[j]) final_score *= 3;
                else if (pr.shoot_b) final_score *= 2;
                net_scores[i] -= final_score;
                net_scores[j] += final_score;
            }

            const char* name_i = r->players[i] ? r->players[i]->getName() : "P?";
            const char* name_j = r->players[j] ? r->players[j]->getName() : "P?";
            std::printf("[PAIR] %s vs %s => %d\n", name_i, name_j, final_score);
        }
    }

    // -------------------------------------------------
    // 5) 倒水买单：所有负分玩家由倒水玩家买单（多人倒水则平分）
    // -------------------------------------------------
    int foul_cnt = 0;
    for (int i = 0; i < n; ++i) if (fouled[i]) ++foul_cnt;
    if (foul_cnt > 0) {
        int total_bill = 0;
        for (int i = 0; i < n; ++i) {
            if (fouled[i]) continue;
            if (net_scores[i] < 0) {
                total_bill += -net_scores[i];
                net_scores[i] = 0; // 负分由倒水玩家承担
            }
        }
        int each = (foul_cnt > 0) ? (total_bill / foul_cnt) : 0;
        int rem  = (foul_cnt > 0) ? (total_bill % foul_cnt) : 0;
        for (int i = 0; i < n; ++i) {
            if (!fouled[i]) continue;
            int extra = (rem > 0) ? 1 : 0;
            if (rem > 0) --rem;
            net_scores[i] -= (each + extra);
        }
    }

    // -------------------------------------------------
    // 6) 输出全局结算与成就提示
    // -------------------------------------------------
    for (int i = 0; i < n; ++i) {
        PlayerRound* pr = r->players[i];
        if (!pr) continue;
        if (fouled[i]) {
            std::printf("[FOUL] %s 倒水：不参与两两结算，承担买单\n", pr->getName());
        }
        if (homerun[i]) {
            std::printf("[ACHV] %s achieved 全垒打 (x3, no shoot bonus)\n",
                        pr->getName());
        }
        std::printf("[ROUND] %s base=%d net=%d\n",
                    pr->getName(), round_scores[i], net_scores[i]);

        if (pr->hasAchievement(ACHV_ROYAL_STRAIGHT_FLUSH_13)) {
            std::printf("[ACHV] %s achieved 至尊清龙 (Royal Straight Flush 13)!\n",
                        pr->getName());
        }
    }

    // -------------------------------------------------
    // 7) 清理每位玩家的局状态
    // -------------------------------------------------
    for (int i = 0; i < n; ++i) {
        PlayerRound* pr = r->players[i];
        if (!pr) continue;
        // PlayerRound::resetRound() 负责释放 Pattern、重置标记
        pr->resetRound();
    }

    // -------------------------------------------------
    // 8) 释放本局牌堆并复位 Round
    // -------------------------------------------------
    if (r->deck) {
        free(r->deck);
        r->deck = nullptr;
    }
    r->deck_type = 0;
    r->deck_pos  = 0;

    free(pair_results);
    free(homerun);
    free(round_scores);
    free(net_scores);
    free(beat_cnt);
    free(fouled);
    return 0;   // 成功
}
