#include "pattern.h"

#include <cstring>

namespace evaluate
{
    enum CardStatus {
        UNSELECTED = 0,
        SELECTED   = 1,
        IN_PILE    = 2
    };

    enum ActionType {
        ACT_SELECT,
        ACT_DESELECT,
        ACT_ADD_TO_PILE,
        ACT_REMOVE_FROM_PILE
    };

    struct Action {
        ActionType type;
        int        card_idx;
        int        position;
    };

    struct HandManager {
        int  m_hand[13];
        CardStatus m_status[13];
        int  m_pile_cnt[3];
        int  m_pile[3][5];
        static const int MAX_ACTION = 1024;
        Action m_action_stack[MAX_ACTION];
        int    m_action_top;
    };

    static bool validIdx(int idx) { return idx >= 0 && idx < 13; }

    static void pushAction(HandManager *mgr, const Action &a)
    {
        if (mgr->m_action_top < HandManager::MAX_ACTION) {
            mgr->m_action_stack[mgr->m_action_top++] = a;
        }
    }

    HandManager* createManager(const int hand13[13])
    {
        if (!hand13) return nullptr;
        HandManager *mgr = new HandManager;
        memcpy(mgr->m_hand, hand13, sizeof(mgr->m_hand));
        memset(mgr->m_status, UNSELECTED, sizeof(mgr->m_status));
        memset(mgr->m_pile_cnt, 0, sizeof(mgr->m_pile_cnt));
        memset(mgr->m_pile, -1, sizeof(mgr->m_pile));
        mgr->m_action_top = 0;
        return mgr;
    }

    void destroyManager(HandManager *mgr)
    {
        delete mgr;
    }

    const int* managerHand(const HandManager *mgr)
    {
        return mgr ? mgr->m_hand : nullptr;
    }

    bool selectCard(HandManager *mgr, int idx)
    {
        if (!mgr || !validIdx(idx) || mgr->m_status[idx] != UNSELECTED) return false;
        pushAction(mgr, { ACT_SELECT, idx, -1 });
        mgr->m_status[idx] = SELECTED;
        return true;
    }

    bool deselectCard(HandManager *mgr, int idx)
    {
        if (!mgr || !validIdx(idx) || mgr->m_status[idx] != SELECTED) return false;
        pushAction(mgr, { ACT_DESELECT, idx, -1 });
        mgr->m_status[idx] = UNSELECTED;
        return true;
    }

    bool addToPile(HandManager *mgr, int position, int idx)
    {
        if (!mgr || !validIdx(idx) || mgr->m_status[idx] != SELECTED || position < 0 || position > 2) return false;

        int limit = (position == 0) ? 3 : 5;
        if (mgr->m_pile_cnt[position] >= limit) return false;

        pushAction(mgr, { ACT_ADD_TO_PILE, idx, position });
        mgr->m_status[idx] = IN_PILE;
        mgr->m_pile[position][mgr->m_pile_cnt[position]++] = idx;
        return true;
    }

    bool removeFromPile(HandManager *mgr, int position, int idx)
    {
        if (!mgr || !validIdx(idx) || mgr->m_status[idx] != IN_PILE || position < 0 || position > 2) return false;

        int found = -1;
        for (int i = 0; i < mgr->m_pile_cnt[position]; ++i) {
            if (mgr->m_pile[position][i] == idx) { found = i; break; }
        }
        if (found == -1) return false;

        pushAction(mgr, { ACT_REMOVE_FROM_PILE, idx, position });
        mgr->m_status[idx] = SELECTED;
        mgr->m_pile[position][found] = mgr->m_pile[position][mgr->m_pile_cnt[position] - 1];
        mgr->m_pile[position][mgr->m_pile_cnt[position] - 1] = -1;
        --mgr->m_pile_cnt[position];
        return true;
    }

    bool undo(HandManager *mgr)
    {
        if (!mgr || mgr->m_action_top == 0) return false;
        const Action &a = mgr->m_action_stack[--mgr->m_action_top];

        switch (a.type) {
        case ACT_SELECT:
            mgr->m_status[a.card_idx] = UNSELECTED;
            break;
        case ACT_DESELECT:
            mgr->m_status[a.card_idx] = SELECTED;
            break;
        case ACT_ADD_TO_PILE:
            mgr->m_status[a.card_idx] = SELECTED;
            for (int i = 0; i < mgr->m_pile_cnt[a.position]; ++i) {
                if (mgr->m_pile[a.position][i] == a.card_idx) {
                    mgr->m_pile[a.position][i] = mgr->m_pile[a.position][mgr->m_pile_cnt[a.position] - 1];
                    mgr->m_pile[a.position][mgr->m_pile_cnt[a.position] - 1] = -1;
                    --mgr->m_pile_cnt[a.position];
                    break;
                }
            }
            break;
        case ACT_REMOVE_FROM_PILE:
            mgr->m_status[a.card_idx] = IN_PILE;
            mgr->m_pile[a.position][mgr->m_pile_cnt[a.position]++] = a.card_idx;
            break;
        default:
            return false;
        }
        return true;
    }

    bool pileFull(const HandManager *mgr, int position)
    {
        if (!mgr || position < 0 || position > 2) return false;
        int limit = (position == 0) ? 3 : 5;
        return mgr->m_pile_cnt[position] == limit;
    }

    bool submit(HandManager *mgr, Pattern *pat)
    {
        if (!mgr || !pat) return false;
        if (!pileFull(mgr, 0) || !pileFull(mgr, 1) || !pileFull(mgr, 2)) return false;

        for (int pos = 0; pos < 3; ++pos) {
            const int limit = (pos == 0) ? 3 : 5;
            for (int i = 0; i < limit; ++i) {
                int idx = mgr->m_pile[pos][i];
                int card_id = mgr->m_hand[idx];
                if (pos == 0) pat->head[i] = card_id;
                else if (pos == 1) pat->middle[i] = card_id;
                else pat->tail[i] = card_id;
            }
        }
        return true;
    }
}
