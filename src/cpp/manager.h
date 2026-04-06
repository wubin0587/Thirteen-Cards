#ifndef TC_MANAGER_H
#define TC_MANAGER_H

#include "pattern/pattern.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 供 C / Python ctypes 调用的统一句柄类型 */
typedef void* tc_player_round_t;
typedef void* tc_hand_manager_t;

/* -------------------- Pattern -------------------- */
int tc_pattern_init(const int hand13[13], Pattern* out);
int tc_pattern_set_position(Pattern* p, int position, const int* cards, int count);
int tc_pattern_get_position(const Pattern* p, int position, int* out_buf);
int tc_pattern_sort(Pattern* p);
HandResult tc_search_pattern(int position, const int* cards, int cnt);
int tc_dfs_enum_combos(const int hand13[13], DFSCandResult* out, int max_k);

/* -------------------- PlayerRound -------------------- */
tc_player_round_t tc_player_round_create(const char* name);
void tc_player_round_destroy(tc_player_round_t player);
int tc_player_round_receive_hand(tc_player_round_t player, const int hand13[13]);
int tc_player_round_set_position(tc_player_round_t player, int position, const int* cards, int cnt);
int tc_player_round_settle(tc_player_round_t player);
int tc_player_round_get_round_score(tc_player_round_t player);
int tc_player_round_get_total_score(tc_player_round_t player);
const char* tc_player_round_get_name(tc_player_round_t player);
int tc_player_round_has_achievement(tc_player_round_t player, int achievement);

/* -------------------- 交互管理 -------------------- */
tc_hand_manager_t tc_hand_manager_create(const int hand13[13]);
void tc_hand_manager_destroy(tc_hand_manager_t mgr);
int tc_hand_manager_select_card(tc_hand_manager_t mgr, int idx);
int tc_hand_manager_deselect_card(tc_hand_manager_t mgr, int idx);
int tc_hand_manager_add_to_pile(tc_hand_manager_t mgr, int position, int idx);
int tc_hand_manager_remove_from_pile(tc_hand_manager_t mgr, int position, int idx);
int tc_hand_manager_undo(tc_hand_manager_t mgr);
int tc_hand_manager_pile_full(tc_hand_manager_t mgr, int position);
int tc_hand_manager_submit(tc_hand_manager_t mgr, Pattern* pat);

/* -------------------- Round -------------------- */
int tc_round_deal_players(tc_player_round_t* players, int player_cnt);
int tc_round_close_players(tc_player_round_t* players, int player_cnt);

#ifdef __cplusplus
}
#endif

#endif
