// src/cpp/evaluate.cpp
// ---------------------------------------------------------------
//  牌型枚舉與判斷
// ---------------------------------------------------------------

#include "pattern.h"

#include <cstring>

namespace evaluate
{
    struct HandManager;

    const int* managerHand(const HandManager *mgr);

    static void generateComb(const int hand13[13],
                             int start, int depth, int need,
                             int combo[], int position,
                             int out_combos[][5], int &out_cnt)
    {
        if (depth == need) {
            int cards[5];
            for (int i = 0; i < need; ++i) {
                cards[i] = hand13[combo[i]];
            }

            HandResult hr = search_pattern(position, cards, need);
            if (hr.position != -1 &&
                strcmp(hr.hand_name, "High Card") != 0 &&
                strcmp(hr.hand_name, "Unknown") != 0) {
                for (int i = 0; i < need; ++i) out_combos[out_cnt][i] = combo[i];
                ++out_cnt;
            }
            return;
        }

        for (int i = start; i <= 13 - (need - depth); ++i) {
            combo[depth] = i;
            generateComb(hand13, i + 1, depth + 1, need, combo, position,
                         out_combos, out_cnt);
        }
    }

    bool hasValidPattern(HandManager *mgr, int position,
                         int out_combos[][5], int &out_cnt)
    {
        out_cnt = 0;
        if (!mgr || position < 0 || position > 2) return false;

        const int *hand13 = managerHand(mgr);
        if (!hand13) return false;

        const int need = (position == 0) ? 3 : 5;
        int combo[5];
        generateComb(hand13, 0, 0, need, combo, position, out_combos, out_cnt);
        return out_cnt > 0;
    }
}
