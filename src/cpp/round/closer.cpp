#include "round.h"
#include "players/player.h"
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

        int cmp = compare_hand_result(ha, hb);
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
    if (!round_scores || !net_scores || !beat_cnt) {
        if (round_scores) free(round_scores);
        if (net_scores) free(net_scores);
        if (beat_cnt) free(beat_cnt);
        return -4;
    }

    for (int i = 0; i < n; ++i) {
        PlayerRound* pr = r->players[i];
        net_scores[i] = 0;
        beat_cnt[i] = 0;
        if (!pr) {
            round_scores[i] = 0;
            continue;
        }
        int rc = pr->settle();
        round_scores[i] = (rc < 0) ? 0 : rc;
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
        return -4;
    }
    for (int i = 0; i < n * n; ++i) pair_results[i] = {0, 0, false, false};

    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
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
        return -4;
    }
    for (int i = 0; i < n; ++i) {
        homerun[i] = (beat_cnt[i] == n - 1);
    }

    // -------------------------------------------------
    // 4) 计算最终两两输赢：全垒打x3 > 打枪x2 > 基础分
    // -------------------------------------------------
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
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
    // 5) 输出全局结算与成就提示
    // -------------------------------------------------
    for (int i = 0; i < n; ++i) {
        PlayerRound* pr = r->players[i];
        if (!pr) continue;
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
    // 6) 清理每位玩家的局状态
    // -------------------------------------------------
    for (int i = 0; i < n; ++i) {
        PlayerRound* pr = r->players[i];
        if (!pr) continue;
        // PlayerRound::resetRound() 负责释放 Pattern、重置标记
        pr->resetRound();
    }

    // -------------------------------------------------
    // 7) 释放本局牌堆并复位 Round
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
    return 0;   // 成功
}
