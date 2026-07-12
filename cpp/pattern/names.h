#ifndef NAMES_H
#define NAMES_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 十三水牌型中文名称对照表
 *
 * 将 score.h 中的英文 hand_name 映射为中文显示名。
 * 通过 tc_get_hand_name_zh() 查询，未找到时返回英文原名。
 */

const char* tc_get_hand_name_zh(const char* en_name);

#ifdef __cplusplus
}
#endif

#endif // NAMES_H
