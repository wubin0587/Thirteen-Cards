#include "manager.h"

#include "players/player.h"
#include "round/round.h"

#include <stdlib.h>

int tc_pattern_init(const int hand13[13], Pattern* out)
{
    return pattern_init(hand13, out);
}

int tc_pattern_set_position(Pattern* p, int position, const int* cards, int count)
{
    return pattern_set_position(p, position, cards, count);
}

int tc_pattern_get_position(const Pattern* p, int position, int* out_buf)
{
    return pattern_get_position(p, position, out_buf);
}

int tc_pattern_sort(Pattern* p)
{
    return pattern_sort(p);
}

HandResult tc_search_pattern(int position, const int* cards, int cnt)
{
    return search_pattern(position, cards, cnt);
}

tc_player_round_t tc_player_round_create(const char* name)
{
    PlayerRound* p = new PlayerRound(name ? name : "Player");
    return reinterpret_cast<tc_player_round_t>(p);
}

void tc_player_round_destroy(tc_player_round_t player)
{
    PlayerRound* p = reinterpret_cast<PlayerRound*>(player);
    delete p;
}

int tc_player_round_receive_hand(tc_player_round_t player, const int hand13[13])
{
    PlayerRound* p = reinterpret_cast<PlayerRound*>(player);
    if (!p) return -1;
    return p->receiveHand(hand13);
}

int tc_player_round_set_position(tc_player_round_t player, int position, const int* cards, int cnt)
{
    PlayerRound* p = reinterpret_cast<PlayerRound*>(player);
    if (!p) return -1;
    return p->setPosition(position, cards, cnt);
}

int tc_player_round_settle(tc_player_round_t player)
{
    PlayerRound* p = reinterpret_cast<PlayerRound*>(player);
    if (!p) return -1;
    return p->settle();
}

int tc_player_round_get_round_score(tc_player_round_t player)
{
    PlayerRound* p = reinterpret_cast<PlayerRound*>(player);
    if (!p) return -1;
    return p->getRoundScore();
}

int tc_player_round_get_total_score(tc_player_round_t player)
{
    PlayerRound* p = reinterpret_cast<PlayerRound*>(player);
    if (!p) return -1;
    return p->getTotalScore();
}

const char* tc_player_round_get_name(tc_player_round_t player)
{
    PlayerRound* p = reinterpret_cast<PlayerRound*>(player);
    if (!p) return "";
    return p->getName();
}

int tc_player_round_has_achievement(tc_player_round_t player, int achievement)
{
    PlayerRound* p = reinterpret_cast<PlayerRound*>(player);
    if (!p) return 0;
    return p->hasAchievement(static_cast<Achievement>(achievement)) ? 1 : 0;
}

tc_hand_manager_t tc_hand_manager_create(const int hand13[13])
{
    evaluate::HandManager* mgr = evaluate::createManager(hand13);
    return reinterpret_cast<tc_hand_manager_t>(mgr);
}

void tc_hand_manager_destroy(tc_hand_manager_t mgr)
{
    evaluate::destroyManager(reinterpret_cast<evaluate::HandManager*>(mgr));
}

int tc_hand_manager_select_card(tc_hand_manager_t mgr, int idx)
{
    return evaluate::selectCard(reinterpret_cast<evaluate::HandManager*>(mgr), idx) ? 1 : 0;
}

int tc_hand_manager_deselect_card(tc_hand_manager_t mgr, int idx)
{
    return evaluate::deselectCard(reinterpret_cast<evaluate::HandManager*>(mgr), idx) ? 1 : 0;
}

int tc_hand_manager_add_to_pile(tc_hand_manager_t mgr, int position, int idx)
{
    return evaluate::addToPile(reinterpret_cast<evaluate::HandManager*>(mgr), position, idx) ? 1 : 0;
}

int tc_hand_manager_remove_from_pile(tc_hand_manager_t mgr, int position, int idx)
{
    return evaluate::removeFromPile(reinterpret_cast<evaluate::HandManager*>(mgr), position, idx) ? 1 : 0;
}

int tc_hand_manager_undo(tc_hand_manager_t mgr)
{
    return evaluate::undo(reinterpret_cast<evaluate::HandManager*>(mgr)) ? 1 : 0;
}

int tc_hand_manager_pile_full(tc_hand_manager_t mgr, int position)
{
    return evaluate::pileFull(reinterpret_cast<evaluate::HandManager*>(mgr), position) ? 1 : 0;
}

int tc_hand_manager_submit(tc_hand_manager_t mgr, Pattern* pat)
{
    return evaluate::submit(reinterpret_cast<evaluate::HandManager*>(mgr), pat) ? 1 : 0;
}

int tc_round_deal_players(tc_player_round_t* players, int player_cnt)
{
    if (!players || player_cnt <= 0) return ROUND_ERR_NULL;

    PlayerRound** round_players = reinterpret_cast<PlayerRound**>(players);
    Round round;
    int rc = round_init(&round, round_players, player_cnt);
    if (rc != 0) return rc;

    rc = round_deal(&round);
    round_cleanup(&round);
    return rc;
}

int tc_round_close_players(tc_player_round_t* players, int player_cnt)
{
    if (!players || player_cnt <= 0) return ROUND_ERR_NULL;

    PlayerRound** round_players = reinterpret_cast<PlayerRound**>(players);
    Round round;
    int rc = round_init(&round, round_players, player_cnt);
    if (rc != 0) return rc;

    rc = round_close(&round);
    return rc;
}
