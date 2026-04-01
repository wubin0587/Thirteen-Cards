#include "round.h"
#include "players/player.h"
#include <cstdio>
#include <cstdlib>

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
    // 1) 结算每位玩家，收集得分
    // -------------------------------------------------
    int* scores = (int*)malloc(sizeof(int) * n);
    if (!scores) return -4;            // 内存分配失败

    for (int i = 0; i < n; ++i) {
        PlayerRound* pr = r->players[i];
        if (!pr) {
            scores[i] = 0;
            continue;
        }
        // settle() 返回本局总分，负数表示内部错误
        int rc = pr->settle();
        scores[i] = (rc < 0) ? 0 : rc;
    }

    // -------------------------------------------------
    // 2) 两两比较得分并打印结果
    // -------------------------------------------------
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            const char* name_i = r->players[i]->getName();
            const char* name_j = r->players[j]->getName();

            if (scores[i] > scores[j]) {
                std::printf("[WIN]  %s ( %d )  beats  %s ( %d )\n",
                            name_i, scores[i], name_j, scores[j]);
            } else if (scores[i] < scores[j]) {
                std::printf("[LOSS] %s ( %d )  loses to %s ( %d )\n",
                            name_i, scores[i], name_j, scores[j]);
            } else {
                std::printf("[TIE]  %s ( %d )  =  %s ( %d )\n",
                            name_i, scores[i], name_j, scores[j]);
            }
        }
    }

    // -------------------------------------------------
    // 3) 特殊成就提示（全垒打、至尊清龙等）
    // -------------------------------------------------
    for (int i = 0; i < n; ++i) {
        PlayerRound* pr = r->players[i];
        if (!pr) continue;

        // “全垒打” – 中墩或尾墩出现 Five of a Kind
        if (pr->hasAchievement(ACHV_FIVE_OF_A_KIND_MIDDLE) ||
            pr->hasAchievement(ACHV_FIVE_OF_A_KIND_TAIL)) {
            std::printf("[ACHV] %s achieved 全垒打 (Five of a Kind)!\n",
                        pr->getName());
        }

        // “至尊清龙” – 13 张同花顺
        if (pr->hasAchievement(ACHV_ROYAL_STRAIGHT_FLUSH_13)) {
            std::printf("[ACHV] %s achieved 至尊清龙 (Royal Straight Flush 13)!\n",
                        pr->getName());
        }

        // 其它成就可自行在此添加，例如：
        // if (pr->hasAchievement(ACHV_STRAIGHT_13)) { ... }
    }

    // -------------------------------------------------
    // 4) 清理每位玩家的局状态
    // -------------------------------------------------
    for (int i = 0; i < n; ++i) {
        PlayerRound* pr = r->players[i];
        if (!pr) continue;
        // PlayerRound::resetRound() 负责释放 Pattern、重置标记
        pr->resetRound();
    }

    // -------------------------------------------------
    // 5) 释放本局牌堆并复位 Round
    // -------------------------------------------------
    if (r->deck) {
        free(r->deck);
        r->deck = nullptr;
    }
    r->deck_type = 0;
    r->deck_pos  = 0;

    // 释放临时得分数组
    free(scores);
    return 0;   // 成功
}