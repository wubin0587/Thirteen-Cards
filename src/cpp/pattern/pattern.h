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
 *
 * 结构体仅负责存储数据，不进行任何牌型判定。
 */
typedef struct {
    int hand[13];      /**< 原始 13 张手牌 */
    int head[3];       /**< 头墩（3 张） */
    int middle[5];     /**< 中墩（5 张） */
    int tail[5];       /**< 尾墩（5 张） */
} Pattern;

/* --------------------------------------------------------------
 * 2. 接口函数（C 风格，便于跨语言调用）
 * -------------------------------------------------------------- */

/**
 * @brief 用完整手牌初始化 Pattern，仅复制 hand。
 *
 * @param hand13 长度为 13 的整型数组，存放牌号（0~103）。
 * @param out    指向已分配好的 Pattern 对象的指针。
 * @return 0 成功，非 0 为错误（如参数为空）。
 */
int pattern_init(const int hand13[13], Pattern* out);

/**
 * @brief 读取指定墩位的牌。
 *
 * @param p        已初始化的 Pattern 指针。
 * @param position 0=head, 1=middle, 2=tail。
 * @param out_buf  用于存放返回牌号的缓冲区（size >= 3/5）。
 * @return 0 成功，非 0 为错误（如 position 超出范围）。
 */
int pattern_get_position(const Pattern* p, int position, int* out_buf);

/**
 * @brief 设置指定墩位的牌（用户提交）。
 *
 * @param p        已初始化的 Pattern 指针。
 * @param position 同上（0=head,1=middle,2=tail）。
 * @param new_cards 指向新牌号数组的指针。
 * @param count    new_cards 元素数量（head 必须为 3，middle/tail 必须为 5）。
 * @return 0 成功，非 0 为错误。
 */
int pattern_set_position(Pattern* p, int position,
                        const int* new_cards, int count);

/**
 * @brief 对 hand 以及已经设置好的每一墩位进行升序排序（按 id）。
 *
 * 只会对已写入的数组进行排序；若某墩位尚未写入（内容未定义），
 * 该函数仍会安全返回，不会对其进行排序。
 *
 * @param p 已初始化且可能已写入墩位的 Pattern 指针。
 * @return 0 成功，非 0 为错误（如 p 为 NULL）。
 */
int pattern_sort(Pattern* p);

#ifdef __cplusplus
}
#endif

#endif /* PATTERN_H */