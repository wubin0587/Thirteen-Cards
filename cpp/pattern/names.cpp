/**
 * @file names.cpp
 * @brief 十三水牌型英文→中文名称对照表
 *
 * 与 score.h 的 HandTableEntry 一一对应，提供完整的
 * 常规牌型 + 多副牌专属 + 特殊牌型的中文译名。
 */

#include <string.h>
#include "names.h"

/* 查表条目 */
typedef struct {
    const char* en;
    const char* zh;
} NameEntry;

/* 常规牌型 (REGULAR_HANDS) */
static const NameEntry REGULAR_NAMES[] = {
    /* 头墩 */
    { "High Card",              "高牌" },
    { "Pair",                   "对子" },
    { "Three of a Kind",        "三条" },
    /* 中墩 */
    { "One Pair",               "对子" },
    { "Two Pair",               "两对" },
    { "Straight",               "顺子" },
    { "Flush",                  "同花" },
    { "Full House",             "葫芦" },
    { "Four of a Kind",         "铁支" },
    { "Straight Flush",         "同花顺" },
    /* 尾墩 */
    /* (重复的同上条目省略，由函数遍历匹配) */
};

/* 多副牌专属 (MULTI_DECK_HANDS) */
static const NameEntry MULTI_DECK_NAMES[] = {
    { "Five of a Kind",         "五同" },
};

/* 特殊牌型 (SPECIAL_HANDS) */
static const NameEntry SPECIAL_NAMES[] = {
    { "Three Straight",         "三顺子" },
    { "Three Flush",            "三同花" },
    { "Six and Half Pair",      "六对半" },
    { "Five Pair Three",        "五对三条" },
    { "Four Three of a Kind",   "四套三条" },
    { "Same Color",             "凑一色" },
    { "All Small",              "全小" },
    { "All Big",                "全大" },
    { "Three Four of a Kind",   "三分天下" },
    { "Three Straight Flush",   "三同花顺" },
    { "Twelve Royals",          "十二皇族" },
    { "Straight 13",            "一条龙" },
    { "Royal Straight Flush 13","至尊清龙" },
};

/* 别名映射 (Dart 端可能传入的变体写法) */
static const NameEntry ALIAS_NAMES[] = {
    { "high card",              "高牌" },
    { "one pair",               "对子" },
    { "two pairs",              "两对" },
    { "three of a kind",        "三条" },
    { "trips",                  "三条" },
    { "three",                  "三条" },
    { "four of a kind",         "铁支" },
    { "four",                   "铁支" },
    { "five of a kind",         "五同" },
    { "five",                   "五同" },
    { "same color",             "凑一色" },
    { "all small",              "全小" },
    { "all big",                "全大" },
};

static int _streq(const char* a, const char* b) {
    if (!a || !b) return 0;
    return strcmp(a, b) == 0;
}

static int _streq_ci(const char* a, const char* b) {
    if (!a || !b) return 0;
    while (*a && *b) {
        char ca = *a++;
        char cb = *b++;
        if (ca >= 'A' && ca <= 'Z') ca += 32;
        if (cb >= 'A' && cb <= 'Z') cb += 32;
        if (ca != cb) return 0;
    }
    return *a == *b;
}

static const NameEntry* _find(const NameEntry* table, int count, const char* name) {
    for (int i = 0; i < count; i++) {
        if (_streq(table[i].en, name) || _streq_ci(table[i].en, name))
            return &table[i];
    }
    return NULL;
}

const char* tc_get_hand_name_zh(const char* en_name) {
    if (!en_name || en_name[0] == '\0') return "";

    const NameEntry* entry;

    /* 1. 精确匹配常规牌型 */
    entry = _find(REGULAR_NAMES, sizeof(REGULAR_NAMES) / sizeof(REGULAR_NAMES[0]), en_name);
    if (entry) return entry->zh;

    /* 2. 精确匹配多副牌牌型 */
    entry = _find(MULTI_DECK_NAMES, sizeof(MULTI_DECK_NAMES) / sizeof(MULTI_DECK_NAMES[0]), en_name);
    if (entry) return entry->zh;

    /* 3. 精确匹配特殊牌型 */
    entry = _find(SPECIAL_NAMES, sizeof(SPECIAL_NAMES) / sizeof(SPECIAL_NAMES[0]), en_name);
    if (entry) return entry->zh;

    /* 4. 别名匹配 (大小写不敏感) */
    entry = _find(ALIAS_NAMES, sizeof(ALIAS_NAMES) / sizeof(ALIAS_NAMES[0]), en_name);
    if (entry) return entry->zh;

    /* 5. 未找到：返回英文原名 */
    return en_name;
}
