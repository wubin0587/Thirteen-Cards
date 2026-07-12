#ifndef SCORE_H
#define SCORE_H

#include <cstring>

namespace thirteencards {

// 位置定义
enum Position {
    POS_HEAD = 0,   // 头墩 (3张牌)
    POS_MIDDLE = 1, // 中墩 (5张牌)
    POS_TAIL = 2,   // 尾墩/底墩 (5张牌)
    POS_SPECIAL = 3 // 特殊牌型 (13张牌)
};

// 查表条目结构
struct HandTableEntry {
    int position;       // 位置：0头, 1中, 2尾, 3特殊
    const char* hand_name; // 牌型英文名
    int rank_order;     // 比较顺序(唯一，数值越大牌型越大)
    int score;          // 分数(水数)
};

// ============================================================================
// 福建十三水牌型分数查表
// 涵盖：常规牌型、多副牌专属牌型、特殊牌型(报到)
// ============================================================================

// 常规牌型查表 (单副牌/多副牌通用基础牌型)
static const HandTableEntry REGULAR_HANDS[] = {
    // ==================== 头墩 (3张牌) ====================
    // 头墩只有3张牌，只能组成：乌龙、对子、三条
    { POS_HEAD, "High Card",      1,  1 },  // 乌龙/散牌
    { POS_HEAD, "Pair",           2,  1 },  // 对子
    { POS_HEAD, "Three of a Kind", 4,  3 }, // 三条 (三尖刀/冲三) - 3水
    
    // ==================== 中墩 (5张牌) ====================
    { POS_MIDDLE, "High Card",      1,  1 },  // 乌龙/散牌
    { POS_MIDDLE, "One Pair",       2,  1 },  // 对子
    { POS_MIDDLE, "Two Pair",       3,  1 },  // 两对
    { POS_MIDDLE, "Three of a Kind", 4,  1 }, // 三条
    { POS_MIDDLE, "Straight",       5,  1 },  // 顺子
    { POS_MIDDLE, "Flush",          6,  1 },  // 同花
    { POS_MIDDLE, "Full House",     7,  2 },  // 葫芦 - 中墩葫芦2水
    { POS_MIDDLE, "Four of a Kind", 8,  8 },  // 铁支/四条 - 中墩8水
    { POS_MIDDLE, "Straight Flush", 9, 10 },  // 同花顺 - 中墩10水
    
    // ==================== 尾墩/底墩 (5张牌) ====================
    { POS_TAIL, "High Card",      1,  1 },  // 乌龙/散牌
    { POS_TAIL, "One Pair",       2,  1 },  // 对子
    { POS_TAIL, "Two Pair",       3,  1 },  // 两对
    { POS_TAIL, "Three of a Kind", 4,  1 }, // 三条
    { POS_TAIL, "Straight",       5,  1 },  // 顺子
    { POS_TAIL, "Flush",          6,  1 },  // 同花
    { POS_TAIL, "Full House",     7,  1 },  // 葫芦
    { POS_TAIL, "Four of a Kind", 8,  4 },  // 铁支/四条 - 底墩4水
    { POS_TAIL, "Straight Flush", 9,  5 },  // 同花顺 - 底墩5水
};

// 多副牌专属牌型查表 (两副牌及以上适用)
// 只有五同是多副牌专属的常规牌型，六同及以上属于特殊牌型
static const HandTableEntry MULTI_DECK_HANDS[] = {
    // ==================== 中墩 (5张牌) - 五同 ====================
    { POS_MIDDLE, "Five of a Kind",  10, 12 },  // 五同 - 中墩12水
    
    // ==================== 尾墩/底墩 (5张牌) - 五同 ====================
    { POS_TAIL, "Five of a Kind",  10,  6 },  // 五同 - 底墩6水
};

// 特殊牌型查表 (报到牌型 - 13张牌组合)
// rank_order: 数值越大牌型越大 (1为最小，13为最大)
// score: 分数采用最经典的高分制 (最大108水制)
static const HandTableEntry SPECIAL_HANDS[] = {
    // 等级1: 三顺子 - 三墩牌各自都是顺子 (最小)
    { POS_SPECIAL, "Three Straight",          1,   6 },
    
    // 等级2: 三同花 - 三墩牌各自都是同花
    { POS_SPECIAL, "Three Flush",             2,   6 },
    
    // 等级3: 六对半 - 13张牌包含6个对子+1张单牌
    { POS_SPECIAL, "Six and Half Pair",       3,   6 },
    
    // 等级4: 五对三条 - 13张牌包含5个对子+1个三条
    { POS_SPECIAL, "Five Pair Three",         4,   6 },
    
    // 等级5: 四套三条 - 13张牌包含4个三条
    { POS_SPECIAL, "Four Three of a Kind",    5,   6 },
    
    // 等级6: 凑一色 - 13张牌全部为黑或全部为红
    { POS_SPECIAL, "Same Color",              6,  10 },
    
    // 等级7: 全小 - 13张牌的点数全部在2到8之间
    { POS_SPECIAL, "All Small",               7,  10 },
    
    // 等级8: 全大 - 13张牌的点数全部在8到A之间
    { POS_SPECIAL, "All Big",                 8,  10 },
    
    // 等级9: 三分天下 (三套炸) - 13张牌中有3个铁支(四条)
    { POS_SPECIAL, "Three Four of a Kind",    9,  20 },
    
    // 等级10: 三同花顺 - 13张牌可分为三墩，且三墩均为同花顺
    { POS_SPECIAL, "Three Straight Flush",    10,  20 },
    
    // 等级11: 十二皇族 - 13张牌中有12张由J、Q、K、A组成
    { POS_SPECIAL, "Twelve Royals",           11,  24 },
    
    // 等级12: 一条龙 (十三水) - 13张牌从A到K点数各不相同
    { POS_SPECIAL, "Straight 13",             12,  36 },
    
    // 等级13: 至尊清龙 (同花十三水) - 13张牌从A到K且花色全部相同 (最大)
    { POS_SPECIAL, "Royal Straight Flush 13", 13, 108 },
};

// 完整查表 (合并所有牌型)
static const HandTableEntry ALL_HANDS[] = {
    // 常规牌型
    { POS_HEAD, "High Card",      1,  1 },
    { POS_HEAD, "Pair",           2,  1 },
    { POS_HEAD, "Three of a Kind", 4,  3 },
    
    { POS_MIDDLE, "High Card",      1,  1 },
    { POS_MIDDLE, "One Pair",       2,  1 },
    { POS_MIDDLE, "Two Pair",       3,  1 },
    { POS_MIDDLE, "Three of a Kind", 4,  1 },
    { POS_MIDDLE, "Straight",       5,  1 },
    { POS_MIDDLE, "Flush",          6,  1 },
    { POS_MIDDLE, "Full House",     7,  2 },
    { POS_MIDDLE, "Four of a Kind", 8,  8 },
    { POS_MIDDLE, "Straight Flush", 9, 10 },
    
    { POS_TAIL, "High Card",      1,  1 },
    { POS_TAIL, "One Pair",       2,  1 },
    { POS_TAIL, "Two Pair",       3,  1 },
    { POS_TAIL, "Three of a Kind", 4,  1 },
    { POS_TAIL, "Straight",       5,  1 },
    { POS_TAIL, "Flush",          6,  1 },
    { POS_TAIL, "Full House",     7,  1 },
    { POS_TAIL, "Four of a Kind", 8,  4 },
    { POS_TAIL, "Straight Flush", 9,  5 },
    
    // 多副牌专属牌型 (五同)
    { POS_MIDDLE, "Five of a Kind",  10, 12 },
    { POS_TAIL, "Five of a Kind",    10,  6 },
    
    // 特殊牌型 (rank_order: 数值越大牌型越大)
    { POS_SPECIAL, "Three Straight",          1,   6 },  // 三顺子 (最小)
    { POS_SPECIAL, "Three Flush",             2,   6 },  // 三同花
    { POS_SPECIAL, "Six and Half Pair",       3,   6 },  // 六对半
    { POS_SPECIAL, "Five Pair Three",         4,   6 },  // 五对三条
    { POS_SPECIAL, "Four Three of a Kind",    5,   6 },  // 四套三条
    { POS_SPECIAL, "Same Color",              6,  10 },  // 凑一色
    { POS_SPECIAL, "All Small",               7,  10 },  // 全小
    { POS_SPECIAL, "All Big",                 8,  10 },  // 全大
    { POS_SPECIAL, "Three Four of a Kind",    9,  20 },  // 三分天下
    { POS_SPECIAL, "Three Straight Flush",    10,  20 }, // 三同花顺
    { POS_SPECIAL, "Twelve Royals",           11,  24 }, // 十二皇族
    { POS_SPECIAL, "Straight 13",             12,  36 }, // 一条龙
    { POS_SPECIAL, "Royal Straight Flush 13", 13, 108 }, // 至尊清龙 (最大)
};

// 查表大小常量
static const int REGULAR_HANDS_COUNT = sizeof(REGULAR_HANDS) / sizeof(REGULAR_HANDS[0]);
static const int MULTI_DECK_HANDS_COUNT = sizeof(MULTI_DECK_HANDS) / sizeof(MULTI_DECK_HANDS[0]);
static const int SPECIAL_HANDS_COUNT = sizeof(SPECIAL_HANDS) / sizeof(SPECIAL_HANDS[0]);
static const int ALL_HANDS_COUNT = sizeof(ALL_HANDS) / sizeof(ALL_HANDS[0]);

} // namespace thirteencards

#endif // SCORE_H
