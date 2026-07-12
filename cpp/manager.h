#ifndef TC_MANAGER_H
#define TC_MANAGER_H

#include "pattern/pattern.h"
#include "pattern/names.h"
#include "game/game.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 供 C / Python ctypes 调用的统一句柄类型 */
typedef void* tc_player_round_t;
typedef void* tc_hand_manager_t;

/* -------------------- Cards utils -------------------- */
int tc_card_rank(int card_id);
int tc_card_suit(int card_id);

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
int tc_player_round_get_hand(tc_player_round_t player, int out_hand13[13]);
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
int tc_hand_manager_get_card_status(tc_hand_manager_t mgr, int idx);
int tc_hand_manager_get_pile_count(tc_hand_manager_t mgr, int position);
int tc_hand_manager_get_pile_card(tc_hand_manager_t mgr, int position, int index);

/* -------------------- Round -------------------- */
int tc_round_deal_players(tc_player_round_t* players, int player_cnt);
int tc_round_close_players(tc_player_round_t* players, int player_cnt);

/* -------------------- PlayerRound 扩展查询 -------------------- */
int tc_player_round_get_position_result(tc_player_round_t player, int position, HandResult* out);
int tc_player_round_get_net_score(tc_player_round_t player);
int tc_player_round_is_fouled(tc_player_round_t player);
int tc_player_round_is_homerun(tc_player_round_t player);
int tc_player_round_get_shoot_count(tc_player_round_t player);
int tc_player_round_get_shot_count(tc_player_round_t player);

/* -------------------- PlayerStats (历史统计) -------------------- */
typedef void* tc_player_stats_t;

tc_player_stats_t tc_player_stats_create(const char* name);
void tc_player_stats_destroy(tc_player_stats_t stats);
int tc_player_stats_add_round_score(tc_player_stats_t stats, int score);
int tc_player_stats_get_round_count(tc_player_stats_t stats);
int tc_player_stats_get_round_score(tc_player_stats_t stats, int idx);
int tc_player_stats_get_total_score(tc_player_stats_t stats);
unsigned int tc_player_stats_get_achievements(tc_player_stats_t stats);
void tc_player_stats_set_achievements(tc_player_stats_t stats, unsigned int mask);

/* -------------------- 牌型名称中文化 (names.cpp) -------------------- */
const char* tc_get_hand_name_zh(const char* en_name);

/* -------------------- 比较/结算 (closer.cpp) -------------------- */
int tc_compare_head_3cards(const int cards_a[3], const int cards_b[3]);
int tc_compare_five_cards(const int cards_a[5], const int cards_b[5]);
int tc_compare_hand_result(int rank_order_a, int rank_order_b);

#ifdef __cplusplus
}
#endif

#endif
