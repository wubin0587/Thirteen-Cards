// src/cpp/evaluate.cpp
// ---------------------------------------------------------------
//  玩家牌堆（Hand）管理與牌型枚舉
// ---------------------------------------------------------------

#include "pattern.h"
#include "searchPattern.cpp"          // 包含 search_pattern 定義
#include "cards.h"

#include <cstring>   // memset, memcpy
#include <cstdlib>   // qsort (若需要)
#include <cstdio>    // printf (除錯用)

namespace evaluate
{
    // -----------------------------------------------------------
    //  牌的三種狀態
    // -----------------------------------------------------------
    enum CardStatus {
        UNSELECTED = 0,   // 尚未被玩家點選
        SELECTED   = 1,   // 已被點選，但尚未放入墩位
        IN_PILE    = 2    // 已放入指定墩位 (head/middle/tail)
    };

    // -----------------------------------------------------------
    //  操作類型（用於 undo）
    // -----------------------------------------------------------
    enum ActionType {
        ACT_SELECT,        // 選中
        ACT_DESELECT,      // 取消選中
        ACT_ADD_TO_PILE,   // 加入墩位
        ACT_REMOVE_FROM_PILE // 從墩位移走
    };

    struct Action {
        ActionType type;
        int        card_idx;   // 手牌在 hand13[] 中的索引
        int        position;   // 0=head,1=middle,2=tail (僅對 ADD/REMOVE 有意義)
    };

    // -----------------------------------------------------------
    //  玩家手牌管理器
    // -----------------------------------------------------------
    class HandManager {
    public:
        // -----------------------------------------------------------------
        //  建構子 – 需要傳入玩家的 13 張手牌 (已由 PlayerRound::receiveHand
        //  產生)。此時所有牌均為 UNSELECTED。
        // -----------------------------------------------------------------
        explicit HandManager(const int hand13[13])
        {
            memcpy(m_hand, hand13, sizeof(m_hand));
            memset(m_status, UNSELECTED, sizeof(m_status));
            memset(m_pile_cnt, 0, sizeof(m_pile_cnt));
            memset(m_pile, -1, sizeof(m_pile));   // -1 表示空位
            m_action_top = 0;
        }

        // -----------------------------------------------------------------
        //  取得原始手牌 (只讀)
        // -----------------------------------------------------------------
        const int* hand() const { return m_hand; }

        // -----------------------------------------------------------------
        //  取得指定牌的當前狀態 (只讀)
        // -----------------------------------------------------------------
        CardStatus status(int idx) const { return m_status[idx]; }

        // -----------------------------------------------------------------
        //  選中一張牌 (只能從 UNSELECTED 轉為 SELECTED)
        // -----------------------------------------------------------------
        bool selectCard(int idx)
        {
            if (!validIdx(idx) || m_status[idx] != UNSELECTED) return false;
            pushAction({ ACT_SELECT, idx, -1 });
            m_status[idx] = SELECTED;
            return true;
        }

        // -----------------------------------------------------------------
        //  取消選中 (只能從 SELECTED 轉回 UNSELECTED)
        // -----------------------------------------------------------------
        bool deselectCard(int idx)
        {
            if (!validIdx(idx) || m_status[idx] != SELECTED) return false;
            pushAction({ ACT_DESELECT, idx, -1 });
            m_status[idx] = UNSELECTED;
            return true;
        }

        // -----------------------------------------------------------------
        //  把已選中的牌放入指定墩位
        //      position : 0=head(3張), 1=middle(5張), 2=tail(5張)
        // -----------------------------------------------------------------
        bool addToPile(int position, int idx)
        {
            if (!validIdx(idx) ||
                m_status[idx] != SELECTED ||
                position < 0 || position > 2) return false;

            int limit = (position == 0) ? 3 : 5;
            if (m_pile_cnt[position] >= limit) return false; // 已滿

            pushAction({ ACT_ADD_TO_PILE, idx, position });
            m_status[idx] = IN_PILE;
            m_pile[position][m_pile_cnt[position]++] = idx;
            return true;
        }

        // -----------------------------------------------------------------
        //  從墩位中移走一張牌，回到 SELECTED 狀態
        // -----------------------------------------------------------------
        bool removeFromPile(int position, int idx)
        {
            if (!validIdx(idx) ||
                m_status[idx] != IN_PILE ||
                position < 0 || position > 2) return false;

            // 在該墩位的陣列中找出 idx，並把最後一張搬到此位以保持緊湊
            int found = -1;
            for (int i = 0; i < m_pile_cnt[position]; ++i) {
                if (m_pile[position][i] == idx) { found = i; break; }
            }
            if (found == -1) return false;

            pushAction({ ACT_REMOVE_FROM_PILE, idx, position });
            m_status[idx] = SELECTED;
            // 把最後一張搬到 found 位置
            m_pile[position][found] = m_pile[position][m_pile_cnt[position] - 1];
            m_pile[position][m_pile_cnt[position] - 1] = -1;
            --m_pile_cnt[position];
            return true;
        }

        // -----------------------------------------------------------------
        //  撤回最近一次操作 (最多 1024 步)
        // -----------------------------------------------------------------
        bool undo()
        {
            if (m_action_top == 0) return false;
            const Action &a = m_action_stack[--m_action_top];

            switch (a.type) {
            case ACT_SELECT:
                m_status[a.card_idx] = UNSELECTED;
                break;
            case ACT_DESELECT:
                m_status[a.card_idx] = SELECTED;
                break;
            case ACT_ADD_TO_PILE:
                // 逆向：把牌從墩位移回 SELECTED
                m_status[a.card_idx] = SELECTED;
                // 找到該牌在墩位中的位置並移除
                for (int i = 0; i < m_pile_cnt[a.position]; ++i) {
                    if (m_pile[a.position][i] == a.card_idx) {
                        m_pile[a.position][i] = m_pile[a.position][m_pile_cnt[a.position] - 1];
                        m_pile[a.position][m_pile_cnt[a.position] - 1] = -1;
                        --m_pile_cnt[a.position];
                        break;
                    }
                }
                break;
            case ACT_REMOVE_FROM_PILE:
                // 逆向：把牌重新放回墩位
                m_status[a.card_idx] = IN_PILE;
                m_pile[a.position][m_pile_cnt[a.position]++] = a.card_idx;
                break;
            default:
                return false;
            }
            return true;
        }

        // -----------------------------------------------------------------
        //  判斷指定墩位是否已滿 (head:3, middle/tail:5)
        // -----------------------------------------------------------------
        bool pileFull(int position) const
        {
            if (position < 0 || position > 2) return false;
            int limit = (position == 0) ? 3 : 5;
            return m_pile_cnt[position] == limit;
        }

        // -----------------------------------------------------------------
        //  提交：檢查三墩是否都已滿，然後把牌寫入 Pattern
        //  (由外部呼叫 pattern_set_position)
        // -----------------------------------------------------------------
        bool submit(Pattern *pat) const
        {
            if (!pat) return false;
            // 必須全部滿
            if (!pileFull(0) || !pileFull(1) || !pileFull(2)) return false;

            // 把牌號寫入 Pattern 結構
            for (int pos = 0; pos < 3; ++pos) {
                const int limit = (pos == 0) ? 3 : 5;
                for (int i = 0; i < limit; ++i) {
                    int idx = m_pile[pos][i];
                    int card_id = m_hand[idx];
                    // 直接寫入內部陣列
                    if (pos == 0) pat->head[i]   = card_id;
                    else if (pos == 1) pat->middle[i] = card_id;
                    else pat->tail[i] = card_id;
                }
            }
            return true;
        }

        // -----------------------------------------------------------------
        //  判斷某個墩位是否存在「非 High Card」的合法牌型
        //  若存在，返回 true，並把所有符合條件的組合寫入 out_combos。
        //  每個組合以卡牌索引 (0~12) 表示，最多 C(13,5)=1287 組。
        // -----------------------------------------------------------------
        bool hasValidPattern(int position, int out_combos[][5], int &out_cnt) const
        {
            out_cnt = 0;
            if (position < 0 || position > 2) return false;
            const int need = (position == 0) ? 3 : 5;

            // 只需要遍歷 hand 中的所有組合
            int combo[5];
            generateComb(0, 0, need, combo, position, out_combos, out_cnt);
            return out_cnt > 0;
        }

    private:
        // -----------------------------------------------------------------
        //  內部資料
        // -----------------------------------------------------------------
        int  m_hand[13];                 // 原始 13 張牌的 id
        CardStatus m_status[13];         // 每張牌的狀態
        int  m_pile_cnt[3];              // 每個墩位已放入的牌數
        int  m_pile[3][5];               // 存放手牌在 hand[] 中的索引
        // 簡易操作棧 (最多 1024 步)
        static const int MAX_ACTION = 1024;
        Action m_action_stack[MAX_ACTION];
        int    m_action_top;

        // -----------------------------------------------------------------
        //  檢查 idx 是否在合法範圍內
        // -----------------------------------------------------------------
        bool validIdx(int idx) const { return idx >= 0 && idx < 13; }

        // -----------------------------------------------------------------
        //  壓入操作棧
        // -----------------------------------------------------------------
        void pushAction(const Action &a)
        {
            if (m_action_top < MAX_ACTION) {
                m_action_stack[m_action_top++] = a;
            }
        }

        // -----------------------------------------------------------------
        //  組合產生器 + 牌型判斷
        //      depth : 已選的卡數
        //      start : 從 hand[] 哪個位置開始選
        // -----------------------------------------------------------------
        void generateComb(int start, int depth, int need,
                          int combo[], int position,
                          int out_combos[][5], int &out_cnt) const
        {
            if (depth == need) {
                // 把選出的卡牌 id 組成陣列，交給 search_pattern 判斷
                int cards[5];
                for (int i = 0; i < need; ++i) {
                    cards[i] = m_hand[combo[i]];
                }
                // 使用 search_pattern 取得手牌類型
                HandResult hr = search_pattern(position, cards, need);
                // 排除 High Card / Unknown
                if (hr.position != -1 &&
                    strcmp(hr.hand_name, "High Card") != 0 &&
                    strcmp(hr.hand_name, "Unknown") != 0) {
                    // 保存此組合 (以 hand[] 索引形式)
                    for (int i = 0; i < need; ++i) out_combos[out_cnt][i] = combo[i];
                    ++out_cnt;
                }
                return;
            }

            // 剪枝：剩餘可選的數量不足時直接返回
            for (int i = start; i <= 13 - (need - depth); ++i) {
                combo[depth] = i;
                generateComb(i + 1, depth + 1, need, combo, position,
                             out_combos, out_cnt);
            }
        }
    };

    // -----------------------------------------------------------------
    //  為外部提供的簡易介面
    // -----------------------------------------------------------------
    // 建立管理器 (返回指標，呼叫者負責 delete)
    inline HandManager* createManager(const int hand13[13])
    {
        return new HandManager(hand13);
    }

    // 釋放管理器
    inline void destroyManager(HandManager *mgr)
    {
        delete mgr;
    }

    // 下面的函式全部是對 HandManager 的薄封裝，方便在
    // Python / PowerShell / 其他語言層直接呼叫。

    inline bool selectCard(HandManager *mgr, int idx)            { return mgr && mgr->selectCard(idx); }
    inline bool deselectCard(HandManager *mgr, int idx)          { return mgr && mgr->deselectCard(idx); }
    inline bool addToPile(HandManager *mgr, int pos, int idx)    { return mgr && mgr->addToPile(pos, idx); }
    inline bool removeFromPile(HandManager *mgr, int pos, int idx){ return mgr && mgr->removeFromPile(pos, idx); }
    inline bool undo(HandManager *mgr)                          { return mgr && mgr->undo(); }
    inline bool submit(HandManager *mgr, Pattern *pat)          { return mgr && pat && mgr->submit(pat); }

    // 判斷是否存在合法牌型，並把所有符合的組合返回給呼叫端
    // out_combos 必須是 [max_comb][5] 的緩衝，max_comb 建議設為 1300
    inline bool hasValidPattern(HandManager *mgr, int pos,
                                int out_combos[][5], int &out_cnt)
    {
        return mgr && mgr->hasValidPattern(pos, out_combos, out_cnt);
    }
} // namespace evaluate