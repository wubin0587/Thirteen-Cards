#ifndef CARDS_H
#define CARDS_H

#ifdef __cplusplus
extern "C" {
#endif

/* --------------------------------------------------------------
 * 1. 枚举
 * -------------------------------------------------------------- */
enum CardEnum {
    D2 = 0,  C2,  H2,  S2,
    D3,  C3,  H3,  S3,
    D4,  C4,  H4,  S4,
    D5,  C5,  H5,  S5,
    D6,  C6,  H6,  S6,
    D7,  C7,  H7,  S7,
    D8,  C8,  H8,  S8,
    D9,  C9,  H9,  S9,
    D10, C10, H10, S10,
    DJ,  CJ,  HJ,  SJ,
    DQ,  CQ,  HQ,  SQ,
    DK,  CK,  HK,  SK,
    DA,  CA,  HA,  SA,

    CARD_DECK2_BASE = 52,
    CARD_DECK3_BASE = 104
};

/* --------------------------------------------------------------
 * 2. 工具函数（纯C风格）
 * -------------------------------------------------------------- */

static inline int card_rank(int card_id) {
    return card_id % 13;
}

static inline int card_suit(int card_id) {
    return card_id / 13;
}

static inline char suit_char(int suit) {
    static const char suit_tbl[4] = {'D','C','H','S'};
    return (suit >= 0 && suit < 4) ? suit_tbl[suit] : '?';
}

static inline const char* rank_str(int rank) {
    static const char* rank_tbl[13] = {
        "2","3","4","5","6","7","8","9","10","J","Q","K","A"
    };
    return (rank >= 0 && rank < 13) ? rank_tbl[rank] : "?";
}

#ifdef __cplusplus
}
#endif

#endif /* CARDS_H */