#ifndef PLAYER_H
#define PLAYER_H

#include "pattern/pattern.h"

#ifdef __cplusplus
extern "C" {
#endif

/* --------------------------------------------------------------
 *  成就枚举（对应特殊牌型或高分普通牌型），使用 32 位位图保存
 * -------------------------------------------------------------- */
typedef enum {
    ACHV_ROYAL_STRAIGHT_FLUSH_13 = 0,   // 至尊清龙
    ACHV_STRAIGHT_13             = 1,   // 一条龙
    ACHV_TWELVE_ROYALS           = 2,   // 十二皇族
    ACHV_THREE_STRAIGHT_FLUSH    = 3,   // 三同花顺
    ACHV_THREE_FOUR_OF_A_KIND    = 4,   // 三分天下
    ACHV_FIVE_OF_A_KIND_MIDDLE   = 5,   // 中墩五同
    ACHV_FIVE_OF_A_KIND_TAIL     = 6,   // 尾墩五同
    ACHV_MAX                     = 32   // 位图上限（32 位）
} Achievement;

/* --------------------------------------------------------------
 *  前置声明（实现位于 player.cpp）
 * -------------------------------------------------------------- */
class Player;
class PlayerRound;
class PlayerStats;

#ifdef __cplusplus
}
#endif

/* -----------------------------------------------------------------
 *  基础类 Player
 * ----------------------------------------------------------------- */
class Player {
protected:
    char*   m_name;                // UTF‑8 名称（malloc 管理）
    int     m_totalScore;          // 累计总分
    unsigned int m_achievements;   // 32 位位图

    /* 内部工具：复制 UTF‑8 字符串 */
    static char* dup_utf8(const char* src);

public:
    explicit Player(const char* name = "Player");
    virtual ~Player();

    /* 名称 ------------------------------------------------------ */
    const char* getName() const;
    void        setName(const char* name);

    /* 分数 ------------------------------------------------------ */
    int  getTotalScore() const;
    void addScore(int delta);          // 累加

    /* 成就 ------------------------------------------------------ */
    void addAchievement(Achievement a);
    bool hasAchievement(Achievement a) const;
    unsigned int getAchievements() const { return m_achievements; }
    void setAchievements(unsigned int mask) { m_achievements = mask; }
};

/* -----------------------------------------------------------------
 *  本局玩家（持有手牌 Pattern）
 * ----------------------------------------------------------------- */
class PlayerRound : public Player {
private:
    Pattern* m_pat;        // 由 pattern_init / pattern_destroy 管理
    int            m_roundScore; // 本局得分，-1 表示未结算
    bool           m_isSpecial;  // true 表示已经是特殊 13 张牌型
    HandResult     m_specialResult; // 特殊牌型缓存（非特殊时为 Unknown）

    /* ---- 结算缓存（由 round_close 写入，供 C API 读取） ---- */
    int  m_settledNetScore;    // 本局净得分（含倍率/倒水调整后）
    bool m_settledFouled;      // 是否倒水
    bool m_settledHomerun;     // 是否全垒打
    int  m_settledShootCnt;    // 打枪次数：赢了三墩的对手数
    int  m_settledShotCnt;     // 被打枪次数：被对手赢了三墩的次数

public:
    explicit PlayerRound(const char* name = "RoundPlayer");
    virtual ~PlayerRound();

    /* 接收 13 张手牌 ------------------------------------------------
     * 若手牌属于 13 张特殊牌型（search_pattern(3,…,13) 返回非
     * “Unknown”），则直接记分、解锁成就并把 m_isSpecial 设为 true。
     * 返回 0 表示成功，非 0 为错误码。 */
    int receiveHand(const int hand13[13]);

    /* 提交墩位 ----------------------------------------------------
     * 仅在非特殊牌型（m_isSpecial == false）时可调用。 */
    int setPosition(int position, const int* cards, int cnt);

    /* 结算本局 ----------------------------------------------------
     * - 若是特殊牌型，直接返回已经算好的 m_roundScore。
     * - 否则依据三墩计算分数、累计总分并检测成就。 */
    int settle();

    /* 读取本局得分（结算后才有意义） --------------------------- */
    int getRoundScore() const;
    bool isSpecialHand() const;
    HandResult getSpecialResult() const;
    int getPositionResult(int position, HandResult* out) const;
    int getHand(int out_hand13[13]) const;
    int getPositionCards(int position, int* out_cards5) const;
    void resetRound();

    /* 结算缓存（round_close 写入后只读） --------------------- */
    int  getSettledNetScore() const { return m_settledNetScore; }
    bool getSettledFouled()   const { return m_settledFouled; }
    bool getSettledHomerun()  const { return m_settledHomerun; }
    int  getSettledShootCnt() const { return m_settledShootCnt; }
    int  getSettledShotCnt()  const { return m_settledShotCnt; }

    /* 结算缓存写入（仅 round_close 调用） --------------------- */
    void setSettledNetScore(int v) { m_settledNetScore = v; }
    void setSettledFouled(bool v)  { m_settledFouled = v; }
    void setSettledHomerun(bool v) { m_settledHomerun = v; }
    void setSettledShootCnt(int v) { m_settledShootCnt = v; }
    void setSettledShotCnt(int v)  { m_settledShotCnt = v; }
};

/* -----------------------------------------------------------------
 *  统计玩家（保存每局得分历史）
 * ----------------------------------------------------------------- */
class PlayerStats : public Player {
private:
    static const int MAX_ROUNDS = 1024;
    int  m_roundScores[MAX_ROUNDS];
    int  m_roundCount;                 // 已记录局数

public:
    explicit PlayerStats(const char* name = "StatsPlayer");
    virtual ~PlayerStats();

    /* 新增一局已结算的分数 -------------------------------------- */
    int addRoundScore(int roundScore); // 0 成功，-1 失败（超出上限）

    /* 查询历史 ---------------------------------------------------- */
    int getRoundCount() const;
    int getRoundScore(int idx) const; // idx 0‑based，非法返回 -1
};

/* -----------------------------------------------------------------
 *  交互管理（实现位于 interaction.cpp）
 * ----------------------------------------------------------------- */
namespace evaluate {
struct HandManager;

HandManager* createManager(const int hand13[13]);
void destroyManager(HandManager *mgr);

bool selectCard(HandManager *mgr, int idx);
bool deselectCard(HandManager *mgr, int idx);
bool addToPile(HandManager *mgr, int position, int idx);
bool removeFromPile(HandManager *mgr, int position, int idx);
bool undo(HandManager *mgr);
bool pileFull(const HandManager *mgr, int position);

bool submit(HandManager *mgr, Pattern *pat);
int getCardStatus(HandManager *mgr, int idx);
int getPileCount(HandManager *mgr, int position);
int getPileCard(HandManager *mgr, int position, int index);
}

#endif // PLAYER_H
