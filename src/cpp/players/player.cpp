#include "player.h"
#include "pattern.h"

#include <stdlib.h>   // malloc / free
#include <string.h>   // strlen / memcpy / strcmp

/*==================================================================
 *  Player
 *==================================================================*/
char* Player::dup_utf8(const char* src)
{
    if (!src) return nullptr;
    size_t len = strlen(src);
    char* dst = (char*)malloc(len + 1);
    if (!dst) return nullptr;
    memcpy(dst, src, len + 1);
    return dst;
}

Player::Player(const char* name)
    : m_name(nullptr), m_totalScore(0), m_achievements(0)
{
    m_name = dup_utf8(name ? name : "Player");
}
Player::~Player()
{
    if (m_name) free(m_name);
}

/* name ----------------------------------------------------------- */
const char* Player::getName() const { return m_name ? m_name : ""; }
void Player::setName(const char* name)
{
    if (!name) return;
    if (m_name) free(m_name);
    m_name = dup_utf8(name);
}

/* score ---------------------------------------------------------- */
int Player::getTotalScore() const { return m_totalScore; }
void Player::addScore(int delta)   { m_totalScore += delta; }

/* achievement ---------------------------------------------------- */
void Player::addAchievement(Achievement a)
{
    if (a >= 0 && a < ACHV_MAX)
        m_achievements |= (1u << a);
}
bool Player::hasAchievement(Achievement a) const
{
    if (a < 0 || a >= ACHV_MAX) return false;
    return (m_achievements & (1u << a)) != 0;
}

/*==================================================================
 *  PlayerRound
 *==================================================================*/
PlayerRound::PlayerRound(const char* name)
    : Player(name), m_pat(nullptr), m_roundScore(-1), m_isSpecial(false)
{
    /* m_pat 会在 receiveHand 时分配 */
    m_specialResult.position = 3;
    m_specialResult.hand_name = "Unknown";
    m_specialResult.rank_order = 0;
    m_specialResult.score = 0;
}
PlayerRound::~PlayerRound()
{
    if (m_pat) free(m_pat);
}

/*--------------------------------------------------------------
 * 接收 13 张手牌
 *   - 先尝试判定是否为 13 张特殊牌型
 *   - 若是特殊牌型：直接写入分数、解锁成就、标记 m_isSpecial = true
 *   - 若不是：正常创建 Pattern，供后续 setPosition/settle 使用
 *--------------------------------------------------------------*/
int PlayerRound::receiveHand(const int hand13[13])
{
    if (!hand13) return -1;

    /* ---------- 1️⃣ 检测 13 张特殊牌型 ---------- */
    HandResult hr_special = search_pattern(3, const_cast<int*>(hand13), 13);
    if (hr_special.position == 3 && hr_special.score > 0) {
        /* 属于特殊牌型 → 直接记分、解锁成就、标记 special */
        m_roundScore = hr_special.score;
        addScore(hr_special.score);
        m_isSpecial = true;
        m_specialResult = hr_special;

        /* 根据 hand_name 写入对应成就（可自行扩展） */
        if (strcmp(hr_special.hand_name, "Royal Straight Flush 13") == 0)
            addAchievement(ACHV_ROYAL_STRAIGHT_FLUSH_13);
        else if (strcmp(hr_special.hand_name, "Straight 13") == 0)
            addAchievement(ACHV_STRAIGHT_13);
        else if (strcmp(hr_special.hand_name, "Twelve Royals") == 0)
            addAchievement(ACHV_TWELVE_ROYALS);
        else if (strcmp(hr_special.hand_name, "Three Straight Flush") == 0)
            addAchievement(ACHV_THREE_STRAIGHT_FLUSH);
        else if (strcmp(hr_special.hand_name, "Three Four of a Kind") == 0)
            addAchievement(ACHV_THREE_FOUR_OF_A_KIND);
        /* 其它特殊牌型若需要成就，可继续在这里添加 */

        /* 特殊牌型不需要再创建 Pattern，直接返回成功 */
        return 0;
    }

    /* ---------- 2️⃣ 普通 13 张手牌 ---------- */
    if (m_pat) free(m_pat);                 // 先释放旧的（若有）
    m_pat = (Pattern*)malloc(sizeof(Pattern));
    if (!m_pat) return -2;

    int rc = pattern_init(hand13, m_pat);
    if (rc != 0) { free(m_pat); m_pat = nullptr; return rc; }

    pattern_sort(m_pat);                     // hand 升序，后续判定更方便
    m_roundScore = -1;                       // 重置结算状态
    m_isSpecial  = false;
    m_specialResult.position = 3;
    m_specialResult.hand_name = "Unknown";
    m_specialResult.rank_order = 0;
    m_specialResult.score = 0;
    return 0;
}

/*--------------------------------------------------------------
 * 提交墩位（仅在非特殊牌型时可调用）
 *--------------------------------------------------------------*/
int PlayerRound::setPosition(int position, const int* cards, int cnt)
{
    if (m_isSpecial) return -1;                 // 特殊牌型不需要提交
    if (!m_pat || !cards) return -2;
    if (position < 0 || position > 2) return -3;
    if ((position == 0 && cnt != 3) ||
        (position != 0 && cnt != 5)) return -4;

    return pattern_set_position(m_pat, position, cards, cnt);
}

/*--------------------------------------------------------------
 * 结算本局
 *   - 若是特殊牌型，直接返回已经算好的 m_roundScore
 *   - 否则读取三墩、使用 search_pattern 计算分数、累计总分并检测成就
 *--------------------------------------------------------------*/
int PlayerRound::settle()
{
    if (m_isSpecial) {
        /* 已经在 receiveHand 时算好分数，直接返回 */
        return m_roundScore;
    }

    if (!m_pat) return -1;

    /* 读取三墩，任意一墩未写入视为错误 */
    int head[3], middle[5], tail[5];
    if (pattern_get_position(m_pat, 0, head)   != 0) return -2;
    if (pattern_get_position(m_pat, 1, middle)!= 0) return -2;
    if (pattern_get_position(m_pat, 2, tail)   != 0) return -2;

    /* 使用已有的 search_pattern 计算每墩得分 */
    HandResult hr_head   = search_pattern(0, head,   3);
    HandResult hr_middle = search_pattern(1, middle, 5);
    HandResult hr_tail   = search_pattern(2, tail,   5);

    int total = hr_head.score + hr_middle.score + hr_tail.score;
    m_roundScore = total;
    addScore(total);                         // 累计到玩家总分

    /* ------------------- 成就检测 ------------------- */
    // 1) 中、尾墩的 “五同” 成就（仅在双副牌时出现）
    if (hr_middle.position == 1 && strcmp(hr_middle.hand_name, "Five of a Kind") == 0)
        addAchievement(ACHV_FIVE_OF_A_KIND_MIDDLE);
    if (hr_tail.position == 2 && strcmp(hr_tail.hand_name, "Five of a Kind") == 0)
        addAchievement(ACHV_FIVE_OF_A_KIND_TAIL);

    // 2) 其它可能的特殊牌型已经在 receiveHand 时处理，这里不再重复

    return total;
}

/* 读取本局得分 ------------------------------------------------- */
int PlayerRound::getRoundScore() const { return m_roundScore; }
bool PlayerRound::isSpecialHand() const { return m_isSpecial; }
HandResult PlayerRound::getSpecialResult() const { return m_specialResult; }
int PlayerRound::getPositionResult(int position, HandResult* out) const
{
    if (!out) return -1;
    if (position < 0 || position > 2) return -2;
    if (m_isSpecial) return -3;
    if (!m_pat) return -4;

    int cards[5] = {0, 0, 0, 0, 0};
    int cnt = (position == 0) ? 3 : 5;
    if (pattern_get_position(m_pat, position, cards) != 0) return -5;

    *out = search_pattern(position, cards, cnt);
    return 0;
}

/* 重置局状态 ------------------------------------------------- */
void PlayerRound::resetRound()
{
    if (m_pat) {
        free(m_pat);
        m_pat = nullptr;
    }
    m_roundScore = -1;
    m_isSpecial = false;
    m_specialResult.position = 3;
    m_specialResult.hand_name = "Unknown";
    m_specialResult.rank_order = 0;
    m_specialResult.score = 0;
}

/*==================================================================
 *  PlayerStats
 *==================================================================*/
PlayerStats::PlayerStats(const char* name)
    : Player(name), m_roundCount(0)
{
    memset(m_roundScores, 0, sizeof(m_roundScores));
}
PlayerStats::~PlayerStats() {}

/* 新增一局已结算的分数 ---------------------------------------- */
int PlayerStats::addRoundScore(int roundScore)
{
    if (m_roundCount >= MAX_ROUNDS) return -1;   // 超出上限
    m_roundScores[m_roundCount++] = roundScore;
    addScore(roundScore);                         // 同步累计到总分
    return 0;
}

/* 查询历史 ---------------------------------------------------- */
int PlayerStats::getRoundCount() const { return m_roundCount; }
int PlayerStats::getRoundScore(int idx) const
{
    if (idx < 0 || idx >= m_roundCount) return -1;
    return m_roundScores[idx];
}
