// src/cpp/round/dealer.cpp
// ---------------------------------------------------------------
// Fisher‑Yates 洗牌实现 + 简易发牌示例
// ---------------------------------------------------------------

#include <cstdlib>      // rand, srand, RAND_MAX
#include <ctime>        // time
#include <algorithm>    // std::swap
#include <cstring>      // memcpy

#include "round.h"      // Round 结构体声明
#include "players/player.h"   // PlayerRound 前向声明 & 接口

// ----------------------------------------------------------------
// 1) Fisher‑Yates 洗牌
//    对 r->deck[0 .. r->deck_type-1] 进行原地随机置换。
//    这里使用 C 标准库的 rand()，在第一次调用时自动以当前时间为种子。
//
//    返回值：0 成功，<0 为错误码（与 round.h 中的错误码保持一致）
// ----------------------------------------------------------------
int round_shuffle(Round* r)
{
    if (!r) return ROUND_ERR_NULL;
    if (!r->deck) return ROUND_ERR_ALLOC;   // deck 尚未分配

    // 第一次调用时初始化随机数种子
    static bool seeded = false;
    if (!seeded) {
        std::srand(static_cast<unsigned int>(std::time(nullptr)));
        seeded = true;
    }

    // Fisher‑Yates：从后往前挑选一个随机位置与之交换
    for (int i = r->deck_type - 1; i > 0; --i) {
        // 产生 [0, i] 区间的随机整数
        int j = std::rand() % (i + 1);
        std::swap(r->deck[i], r->deck[j]);
    }
    return 0;   // 成功
}

// ----------------------------------------------------------------
// 2) 简易发牌（dealer）
//    - 先调用 round_shuffle 完成洗牌
//    - 按玩家顺序依次取 13 张牌，调用 PlayerRound::receiveHand
//    - 失败时返回负数错误码；成功返回 0
//
//    注意：本函数仅演示发牌流程，实际游戏中可能需要更复杂的
//    牌堆回收、玩家离线等逻辑，这里保持最小实现。
// ----------------------------------------------------------------
int round_deal(Round* r)
{
    if (!r) return ROUND_ERR_NULL;
    if (!r->players) return ROUND_ERR_NULL;
    if (r->player_cnt <= 0) return ROUND_ERR_PLAYER_COUNT;

    // 1) 洗牌
    int rc = round_shuffle(r);
    if (rc != 0) return rc;

    // 2) 为每位玩家发 13 张手牌
    const int HAND_SIZE = 13;
    for (int p = 0; p < r->player_cnt; ++p) {
        // 检查牌堆是否还有足够的牌
        if (r->deck_pos + HAND_SIZE > r->deck_type) {
            // 牌堆不足——理论上不应出现（除非玩家数异常）
            return -100;   // 自定义错误码，表示“牌堆耗尽”
        }

        // 复制 13 张牌到临时数组
        int hand[HAND_SIZE];
        std::memcpy(hand, &r->deck[r->deck_pos], sizeof(int) * HAND_SIZE);
        r->deck_pos += HAND_SIZE;

        // 调用 C++ 接口把手牌交给玩家
        PlayerRound* pr = r->players[p];
        if (!pr) return -101;   // 玩家指针为空
        rc = pr->receiveHand(hand);
        if (rc != 0) {
            // 若玩家接收手牌失败，直接返回错误码
            return rc;
        }
    }

    // 所有玩家均已成功接收手牌
    return 0;
}