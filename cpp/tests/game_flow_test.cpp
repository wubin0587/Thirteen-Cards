#include "manager.h"

#include <cstdio>
#include <cstdlib>

#define CHECK(expr) do { if (!(expr)) { \
    std::fprintf(stderr, "CHECK failed at %s:%d: %s\n", __FILE__, __LINE__, #expr); \
    std::exit(1); \
} } while (0)

int main() {
    tc_game_t game = tc_game_create(4);
    CHECK(game != nullptr);
    CHECK(tc_game_set_seed(game, 20260619) == TC_OK);
    CHECK(tc_game_start_round(game) == TC_OK);
    CHECK(tc_game_get_phase(game) == TC_PHASE_ARRANGING || tc_game_get_phase(game) == TC_PHASE_READY);

    for (int p = 0; p < 4; ++p) {
        int hand[13];
        CHECK(tc_game_get_hand(game, p, hand) == TC_OK);
        if (!tc_game_is_special(game, p)) {
            if (p == 0) {
                CHECK(tc_game_select_card(game, p, 0) == TC_OK);
                CHECK(tc_game_add_to_pile(game, p, 0, 0) == TC_OK);
                CHECK(tc_game_undo(game, p) == TC_OK);
                CHECK(tc_game_undo(game, p) == TC_OK);
                CHECK(tc_game_get_card_status(game, p, 0) == 0);
            }
            TcArrangement recommended{};
            CHECK(tc_game_recommend_arrangement(game, p, 0, &recommended) == TC_OK);
            if (p == 0) {
                TcArrangement invalid = recommended;
                invalid.head[0] = 9999;
                CHECK(tc_game_apply_arrangement(game, p, &invalid) == TC_ERR_CARD_NOT_OWNED);
            }
            CHECK(tc_game_apply_arrangement(game, p, &recommended) == TC_OK);
            CHECK(tc_game_get_arrangement_status(game, p) == TC_ARR_VALID);
            CHECK(tc_game_submit_arrangement(game, p, 0) == TC_OK);
        }
    }

    CHECK(tc_game_get_phase(game) == TC_PHASE_READY);
    CHECK(tc_game_settle(game) == TC_OK);
    CHECK(tc_game_get_phase(game) == TC_PHASE_SETTLED);
    CHECK(tc_game_settle(game) == TC_ERR_ALREADY_SETTLED);

    int net_sum = 0;
    TcPlayerSettlement results[4]{};
    for (int p = 0; p < 4; ++p) {
        TcPlayerSettlement& result = results[p];
        CHECK(tc_game_get_player_settlement(game, p, &result) == TC_OK);
        net_sum += result.round_net_score;
        std::printf("P%d net=%d shoot=%d homerun=%d foul=%d\n", p,
                    result.round_net_score, result.shoot_count,
                    result.homerun, result.fouled);
    }
    for (int p = 0; p < 4; ++p) {
        int valid_opponents = 0;
        for (int q = 0; q < 4; ++q)
            if (p != q && !results[q].fouled) ++valid_opponents;
        const bool expected_homerun = !results[p].fouled &&
            valid_opponents > 0 && results[p].shoot_count == valid_opponents;
        CHECK((results[p].homerun != 0) == expected_homerun);
    }
    CHECK(net_sum == 0);
    CHECK(tc_game_get_pair_count(game) == 6);

    CHECK(tc_game_start_round(game) == TC_OK);
    CHECK(tc_game_get_phase(game) == TC_PHASE_ARRANGING || tc_game_get_phase(game) == TC_PHASE_READY);
    tc_game_destroy(game);
    std::puts("thirteen game flow: OK");
    return 0;
}
