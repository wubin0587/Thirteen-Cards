#ifndef ROUND_H
#define ROUND_H

/*=====================================================================
 *  round.h
 *  ----------
 *  只负责回合（Round）的 **初始化** 与资源回收。
 *
 *  主要职责：
 *   1) 保存外部创建的 PlayerRound* 数组指针（由调用者管理生命周期）。
 *   2) 校验玩家人数是否合法（3~12 人）。
 *   3) 根据人数自动决定使用的牌副数：
 *        3~4 人 → 1 副 (52 张)
 *        5~8 人 → 2 副 (104 张)
 *        9~12 人 → 3 副 (156 张)
 *   4) 为本局创建顺序牌堆（0 … total_cards‑1），后续洗牌/发牌/结算交给其他文件实现。
 *
 *  约束：
 *   - 只使用标准 C 库（malloc / free / memcpy / rand），不使用 STL。
 *   - 所有公开函数返回 0 为成功，负数为错误码（见下方枚举）。
 *====================================================================*/

#include <stdlib.h>   // malloc / free
#include <stdbool.h>  // bool

#include "players/player.h"
#include "cards/cards.h"

#ifdef __cplusplus
extern "C" {
#endif

/*--------------------------------------------------------------
 *  Round 结构体
 *--------------------------------------------------------------*/
typedef struct {
    PlayerRound **players;   /* 外部管理的玩家指针数组               */
    int           player_cnt;/* 玩家数量（必须 3~12）                */
    int           deck_type;/* 实际牌张数 = decks * CARD_DECK2_BASE   */
    int          *deck;      /* 动态分配的牌堆数组，长度为 deck_type   */
    int           deck_pos;  /* 已发出的牌在 deck[] 中的下标（发牌模块维护） */
} Round;

/*--------------------------------------------------------------
 *  错误码（统一负数返回值）
 *--------------------------------------------------------------*/
enum {
    ROUND_ERR_NULL          = -1,   /* 传入指针为空                         */
    ROUND_ERR_ALLOC         = -2,   /* 内存分配失败                         */
    ROUND_ERR_PLAYER_COUNT  = -3,   /* 玩家数量非法（<3 或 >12）           */
    ROUND_ERR_DECK_TYPE     = -4    /* 计算得到的牌张数非法（理论上不可能） */
};

/*--------------------------------------------------------------
 *  round_init
 *
 *  参数:
 *      r            - 待初始化的 Round 指针（不可为 NULL）。
 *      player_array - 已经创建好的 PlayerRound* 数组指针（外部管理）。
 *      player_cnt   - 玩家数量，必须在 3~12 之间。
 *
 *  返回:
 *      0   成功
 *      <0 错误码（见上方枚举）
 *--------------------------------------------------------------*/
static inline int round_init(Round *r,
                             PlayerRound **player_array,
                             int player_cnt)
{
    /* 基础参数检查 */
    if (!r || !player_array)                     return ROUND_ERR_NULL;
    if (player_cnt < 3 || player_cnt > 12)       return ROUND_ERR_PLAYER_COUNT;

    /* 根据人数决定使用的牌副数 */
    int decks = 0;
    if (player_cnt >= 3 && player_cnt <= 4)      decks = 1;
    else if (player_cnt >= 5 && player_cnt <= 8) decks = 2;
    else if (player_cnt >= 9 && player_cnt <= 12)decks = 3;
    else                                         return ROUND_ERR_PLAYER_COUNT; /* 防御性检查 */

    /* 计算实际牌张数 */
    int total_cards = decks * CARD_DECK2_BASE;   /* CARD_DECK2_BASE == 52 */
    if (total_cards <= 0)                       return ROUND_ERR_DECK_TYPE;

    /* 保存玩家信息（不负责释放） */
    r->players    = player_array;
    r->player_cnt = player_cnt;
    r->deck_type  = total_cards;
    r->deck_pos   = 0;

    /* 分配并填充顺序牌堆：0,1,2,...,total_cards-1 */
    r->deck = (int*)malloc(sizeof(int) * total_cards);
    if (!r->deck)                               return ROUND_ERR_ALLOC;

    for (int i = 0; i < total_cards; ++i) {
        r->deck[i] = i;
    }

    return 0;   /* 初始化成功 */
}

/*--------------------------------------------------------------
 *  round_cleanup
 *
 *  释放 round_init 中分配的资源（仅 deck），玩家指针数组
 *  的生命周期仍由外部管理。
 *
 *  参数:
 *      r - 已初始化的 Round（可为 NULL，安全容错）。
 *--------------------------------------------------------------*/
static inline void round_cleanup(Round *r)
{
    if (!r) return;
    if (r->deck) {
        free(r->deck);
        r->deck = NULL;
    }
    r->players    = NULL;
    r->player_cnt = 0;
    r->deck_type  = 0;
    r->deck_pos   = 0;
}

/*--------------------------------------------------------------
 *  round 模块其它实现（定义在 src/cpp/round/*.cpp）
 *--------------------------------------------------------------*/
int round_shuffle(Round *r);
int round_deal(Round *r);
int round_close(Round *r);

#ifdef __cplusplus
}

namespace evaluate {
struct HandManager;
bool hasValidPattern(HandManager *mgr, int position,
                     int out_combos[][5], int &out_cnt);
}
#endif

#endif /* ROUND_H */
