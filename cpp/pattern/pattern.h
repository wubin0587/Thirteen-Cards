#ifndef PATTERN_H
#define PATTERN_H

#ifdef __cplusplus
extern "C" {
#endif

/* --------------------------------------------------------------
 * 1. 数据结构
 * -------------------------------------------------------------- */

/**
 * @brief 玩家手牌结构体。
 *
 * - hand[13]   : 原始 13 张手牌（未排序）。
 * - head[3]    : 头墩（用户提交），未设置时内容未定义。
 * - middle[5]  : 中墩（用户提交），未设置时内容未定义。
 * - tail[5]    : 尾墩（用户提交），未设置时内容未定义。
 */
typedef struct {
    int hand[13];
    int head[3];
    int middle[5];
    int tail[5];
} Pattern;

/* --------------------------------------------------------------
 * 2. 接口函数（C 风格，便于跨语言调用）
 * -------------------------------------------------------------- */

int pattern_init(const int hand13[13], Pattern* out);
int pattern_get_position(const Pattern* p, int position, int* out_buf);
int pattern_set_position(Pattern* p, int position,
                         const int* new_cards, int count);
int pattern_sort(Pattern* p);

/* --------------------------------------------------------------
 * 3. 牌型查询
 * -------------------------------------------------------------- */

/**
 * @brief 牌型查询结果。
 */
typedef struct {
    int         position;   /**< 0=head,1=middle,2=tail,3=special */
    const char* hand_name;
    int         rank_order; /**< 牌型等级，越大越强 */
    int         score;      /**< 水数 */
} HandResult;

HandResult search_pattern(int position, const int* cards, int cnt);

/* --------------------------------------------------------------
 * 4. DFS 枚举结果结构
 * -------------------------------------------------------------- */

/**
 * @brief 单个"有牌型"组成单元。
 *
 *  position 字段**不在此处锁定**：
 *    - card_count == 3  → 只能放头墩
 *    - card_count == 5  → 可放中墩或尾墩，由上层模型决定
 *
 *  上层通过枚举排列（最多 3! = 6 种）配合不倒水约束选择最优分配。
 */
typedef struct {
    int        card_count;   /**< 3 或 5 */
    int        cards[5];     /**< 实际牌号，头墩仅前 3 张有效 */
    HandResult result;       /**< 该组牌的牌型结果（position 字段仅供参考） */
} HandUnit;

/**
 * @brief 一种合法的牌型组合（不指定墩位）。
 *
 *  约束：
 *    - units 中最多 1 个 card_count==3 的单元（头墩候选）
 *    - units 中最多 2 个 card_count==5 的单元（中/尾候选）
 *    - units 总数 1~3
 *    - 存在至少一种墩位分配使得 tail >= middle >= head（不倒水）
 *    - loose_cards 是剩余未锁入任何 unit 的散牌，按点数降序排列
 *
 *  typed_score：所有 unit 的 score 之和（不含散牌墩的评分）。
 *  上层模型负责：
 *    1. 枚举墩位分配排列，验证不倒水
 *    2. 将 loose_cards 分配到空墩
 *    3. 综合计算总期望分
 */
typedef struct {
    int      unit_count;          /**< units 实际数量，1~3 */
    HandUnit units[3];            /**< 有牌型的组成单元，不含散牌 */
    int      typed_score;         /**< units 分数之和 */
    int      loose_count;         /**< 散牌数量，0~10 */
    int      loose_cards[13];     /**< 散牌，按点数降序（card_rank 降序） */
} HandCombo;

/**
 * @brief dfs_enum_combos 的输出结构。
 */
typedef struct {
    int       is_special;       /**< 1 = 命中特殊牌型，此时 combos 无意义 */
    int       special_score;
    const char* special_name;

    int       combo_count;      /**< combos 实际数量 */
    HandCombo combos[128];      /**< Top-K 组合，按 typed_score 降序 */
} DFSCandResult;

/**
 * @brief 使用 DFS 枚举所有合法牌型组合。
 *
 *  输出 typed_score 最高的前 max_k 个不倒水可行的组合。
 *  每个组合包含 1~3 个"有牌型单元" + 剩余散牌，不指定墩位。
 *
 * @param hand13  13 张手牌。
 * @param out     输出结构体，由调用方分配。
 * @param max_k   最多保留的组合数（建议 32~128，上限 128）。
 * @return 0 成功，非 0 错误码。
 */
/* dfs.cpp 对外导出的 DFS 枚举入口 */
int dfs_enum_combos(const int hand13[13], DFSCandResult* out, int max_k);

/* --------------------------------------------------------------
 * 5. 兼容旧接口（保留类型定义，供其他模块过渡期使用）
 * -------------------------------------------------------------- */

typedef struct {
    int        position;
    int        card_count;
    int        cards[5];
    HandResult result;
} TypedPileResult;

typedef struct {
    int             is_special;
    int             special_score;
    const char*     special_name;
    int             typed_score;
    int             typed_count;
    TypedPileResult typed_piles[3];
    int             occupied_positions;
    int             loose_count;
    int             loose_cards[13];
} DFSResult;

#ifdef __cplusplus
}
#endif

#endif /* PATTERN_H */
