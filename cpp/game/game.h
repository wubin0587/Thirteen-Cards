#ifndef TC_GAME_H
#define TC_GAME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* tc_game_t;

enum TcGamePhase {
    TC_PHASE_IDLE = 0,
    TC_PHASE_ARRANGING = 1,
    TC_PHASE_READY = 2,
    TC_PHASE_SETTLED = 3
};

enum TcError {
    TC_OK = 0,
    TC_ERR_NULL = -1,
    TC_ERR_PHASE = -2,
    TC_ERR_PLAYER_COUNT = -3,
    TC_ERR_PLAYER_INDEX = -4,
    TC_ERR_CARD_ID = -5,
    TC_ERR_CARD_NOT_OWNED = -6,
    TC_ERR_DUPLICATE_CARD = -7,
    TC_ERR_PILE_FULL = -8,
    TC_ERR_INCOMPLETE = -9,
    TC_ERR_FOULED = -10,
    TC_ERR_SPECIAL_HAND = -11,
    TC_ERR_ALREADY_SETTLED = -12,
    TC_ERR_ALLOC = -13
};

enum TcArrangementStatus {
    TC_ARR_INCOMPLETE = 0,
    TC_ARR_VALID = 1,
    TC_ARR_FOULED = 2,
    TC_ARR_SPECIAL = 3
};

typedef struct {
    int position;
    int rank_order;
    int score;
    char hand_name[48];
} TcHandResult;

typedef struct {
    int is_special;
    int head[3];
    int middle[5];
    int tail[5];
    TcHandResult head_result;
    TcHandResult middle_result;
    TcHandResult tail_result;
    TcHandResult special_result;
    int utility_score;
} TcArrangement;

typedef struct {
    int player_index;
    int hand[13];
    int head[3];
    int middle[5];
    int tail[5];
    TcHandResult head_result;
    TcHandResult middle_result;
    TcHandResult tail_result;
    TcHandResult special_result;
    int is_special;
    int fouled;
    int homerun;
    int shoot_count;
    int shot_count;
    int round_net_score;
    int total_score;
    uint32_t achievements;
} TcPlayerSettlement;

typedef struct {
    int player_a;
    int player_b;
    int head_cmp;
    int middle_cmp;
    int tail_cmp;
    int winner;
    int base_score;
    int multiplier;
    int final_score;
    int shoot_a;
    int shoot_b;
} TcPairSettlement;

tc_game_t tc_game_create(int player_count);
void tc_game_destroy(tc_game_t game);
int tc_game_set_seed(tc_game_t game, uint64_t seed);
int tc_game_start_round(tc_game_t game);
int tc_game_get_phase(tc_game_t game);
int tc_game_get_player_count(tc_game_t game);
int tc_game_get_hand(tc_game_t game, int player, int out_hand13[13]);
int tc_game_is_special(tc_game_t game, int player);
int tc_game_get_special_result(tc_game_t game, int player, TcHandResult* out);

int tc_game_select_card(tc_game_t game, int player, int card_index);
int tc_game_deselect_card(tc_game_t game, int player, int card_index);
int tc_game_add_to_pile(tc_game_t game, int player, int position, int card_index);
int tc_game_remove_from_pile(tc_game_t game, int player, int position, int card_index);
int tc_game_undo(tc_game_t game, int player);
int tc_game_get_card_status(tc_game_t game, int player, int card_index);
int tc_game_get_pile(tc_game_t game, int player, int position, int* out_cards, int capacity);
int tc_game_get_arrangement_status(tc_game_t game, int player);
int tc_game_submit_arrangement(tc_game_t game, int player, int allow_fouled);

int tc_game_recommend_arrangement(tc_game_t game, int player, int strategy, TcArrangement* out);
int tc_game_apply_arrangement(tc_game_t game, int player, const TcArrangement* arrangement);
int tc_game_auto_arrange(tc_game_t game, int player, int strategy);

int tc_game_settle(tc_game_t game);
int tc_game_get_player_settlement(tc_game_t game, int player, TcPlayerSettlement* out);
int tc_game_get_pair_count(tc_game_t game);
int tc_game_get_pair_settlement(tc_game_t game, int pair_index, TcPairSettlement* out);
const char* tc_error_message(int code);

#ifdef __cplusplus
}
#endif

#endif
