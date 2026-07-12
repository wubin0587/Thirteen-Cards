"""
features.py
-----------
特征工程层。

职责：
  - 将 input.py 返回的原始 Python 数据结构转换为 numpy / torch 张量
  - 定义并维护 MODEL_INPUT_SPEC（供 ONNX 导出对齐 Unity 端输入）
  - 不调用模型，不做 IO

公开接口：
  encode_hand(hand13)              → np.ndarray  shape (13, CARD_DIM)
  encode_combo(combo, hand13)      → np.ndarray  shape (COMBO_DIM,)
  encode_batch_combos(dfs_result, hand13)
                                   → np.ndarray  shape (K, COMBO_DIM)
  attack_potential(combo)          → float   [0,1]  用于 aggression 加成
  defense_stability(combo)         → float   [0,1]  用于 aggression 惩罚
  MODEL_INPUT_SPEC                 → dict    ONNX 输入规范

常量说明：
  CARD_DIM   = 17   （4维花色 one-hot + 13维点数 one-hot）
  COMBO_DIM  = 74   （见下方详细注释）
  MAX_COMBOS = 128  （与 DFSCandResult.combos 上限一致）
"""

from __future__ import annotations

import numpy as np
from typing import List, Dict, Any

from input import (
    HandComboPy,
    DFSCandResultPy,
    HandUnitPy,
    card_rank,
    card_suit,
)

# ============================================================
# 1.  维度常量
# ============================================================

CARD_DIM   = 17   # 单张牌特征维度：4(花色 one-hot) + 13(点数 one-hot)
COMBO_DIM  = 74   # 单个 combo 特征维度（详见 encode_combo 注释）
MAX_COMBOS = 128  # 与 C++ DFSCandResult.combos[128] 一致

# ============================================================
# 2.  ONNX 输入规范（供 train.py export 和 Unity 端对齐）
# ============================================================

MODEL_INPUT_SPEC: Dict[str, Any] = {
    # 手牌序列：13 个 token，每 token 17 维
    "hand_tokens": {
        "shape": (1, 13, CARD_DIM),   # (batch, seq, feat)
        "dtype": "float32",
        "description": "13张手牌的 one-hot 编码，顺序与发牌顺序一致",
    },
    # 候选 combo 特征矩阵：最多 MAX_COMBOS 个 combo，每个 COMBO_DIM 维
    "combo_features": {
        "shape": (1, MAX_COMBOS, COMBO_DIM),
        "dtype": "float32",
        "description": "DFS 枚举的候选组合特征，不足 MAX_COMBOS 时用 0 填充",
    },
    # 有效 combo 数量掩码（避免 padding 位参与 softmax）
    "combo_mask": {
        "shape": (1, MAX_COMBOS),
        "dtype": "float32",
        "description": "1.0=有效 combo，0.0=padding",
    },
}

# ============================================================
# 3.  单张牌编码
# ============================================================

def encode_card(card_id: int) -> np.ndarray:
    """
    将单张牌编码为 17 维 one-hot 向量。

    布局：
      [0:4]   花色 one-hot  (D C H S)
      [4:17]  点数 one-hot  (2 3 4 5 6 7 8 9 10 J Q K A)

    多副牌（card_id >= 52）通过取模自动处理。
    """
    vec = np.zeros(CARD_DIM, dtype=np.float32)
    s = card_suit(card_id)   # 0~3
    r = card_rank(card_id)   # 0~12
    vec[s] = 1.0
    vec[4 + r] = 1.0
    return vec


def encode_hand(hand13: List[int]) -> np.ndarray:
    """
    将 13 张手牌编码为形状 (13, CARD_DIM) 的矩阵。

    每行对应一张牌，行顺序与 hand13 列表顺序一致。
    Transformer 的位置编码由模型内部处理，这里不嵌入。
    """
    assert len(hand13) == 13, f"需要 13 张牌，实际 {len(hand13)} 张"
    return np.stack([encode_card(c) for c in hand13], axis=0)  # (13, 17)


# ============================================================
# 4.  单个 Combo 编码
# ============================================================
#
#  COMBO_DIM = 74 的布局：
#
#  [0]       typed_score（归一化到 [0,1]，除以 MAX_TYPED_SCORE=30）
#  [1]       unit_count / 3.0
#  [2]       loose_count / 13.0
#
#  Unit 0（3张 unit，若无则全0）：
#  [3]       card_count / 5.0
#  [4:7]     result.rank_order one-hot（0~9 → 截断到10档，这里压缩为3位归一化）
#             实际：[rank_order/10, score/10, card_count==3 ? 1 : 0]
#  [7:24]    cards 编码：最多 5 张 × CARD_DIM=17（不足补0）→ 取前 3 张平均池化 → 17维
#             这里改用：3张牌点数分布 (13维) + 花色分布 (4维) = 17维
#
#  Unit 1（5张 unit，slot 0，若无则全0）：
#  [24:44]   同上，5张牌的点数分布13 + 花色分布4 + rank/score/size 各1 = 20维
#
#  Unit 2（5张 unit，slot 1，若无则全0）：
#  [44:64]   同上，20维
#
#  散牌统计：
#  [64:77]   loose_cards 点数频次分布（13维），归一化到 [0,1]（除以可能的最大频次）
#
#  总计：3 + (3+17) + (3+17) + (3+17) + 13 = 3 + 20*3 + 13 = 76... 调整如下：
#
#  重新规划（以简洁优先）：
#  [0]        typed_score / 30.0
#  [1]        unit_count / 3.0
#  [2]        loose_count / 13.0
#  Unit×3（每个unit 10维，共30维）：
#    [3+i*10+0]  card_count==3 ? 1.0 : 0.0
#    [3+i*10+1]  rank_order / 10.0
#    [3+i*10+2]  score / 10.0
#    [3+i*10+3]  最高点数 / 12.0
#    [3+i*10+4]  最低点数 / 12.0
#    [3+i*10+5]  花色种类数 / 4.0（同花顺=1, 同花=1, 散=4）
#    [3+i*10+6]  是否有对子（rank重复）
#    [3+i*10+7]  是否有三条
#    [3+i*10+8]  是否顺子结构
#    [3+i*10+9]  是否同花结构
#  共 3 + 30 = 33 维
#  散牌点数分布（13维）：[33:46]
#  散牌花色分布（4维）：[46:50]
#  散牌最高点数归一化：[50]
#  散牌对子数：[51]
#  全局：手牌点数分布（13维）[52:65]
#  全局：手牌花色分布（4维）[65:69]
#  全局：是否有三条 [69]、四条 [70]、顺子 [71]、同花 [72]、同花顺 [73]
#
#  最终 COMBO_DIM = 74  ✓
#
# ============================================================

_MAX_TYPED_SCORE = 30.0   # 用于归一化 typed_score


def _unit_features(unit: HandUnitPy) -> np.ndarray:
    """将一个 HandUnitPy 编码为 10 维特征向量。"""
    vec = np.zeros(10, dtype=np.float32)
    if unit is None:
        return vec

    cards = unit.cards[:unit.card_count]
    ranks = [card_rank(c) for c in cards]
    suits = [card_suit(c) for c in cards]

    vec[0] = 1.0 if unit.card_count == 3 else 0.0
    vec[1] = unit.result.rank_order / 10.0
    vec[2] = unit.result.score / 10.0
    vec[3] = max(ranks) / 12.0
    vec[4] = min(ranks) / 12.0
    vec[5] = len(set(suits)) / 4.0

    rank_cnt = np.zeros(13, dtype=np.int32)
    for r in ranks:
        rank_cnt[r] += 1
    vec[6] = 1.0 if any(rank_cnt == 2) else 0.0
    vec[7] = 1.0 if any(rank_cnt >= 3) else 0.0

    # 顺子结构：所有点数不同且最大-最小 == card_count-1（或 A-low 顺）
    unique_ranks = sorted(set(ranks))
    is_straight = (
        len(unique_ranks) == unit.card_count and
        (unique_ranks[-1] - unique_ranks[0] == unit.card_count - 1
         or (unit.card_count == 5
             and unique_ranks == [0, 1, 2, 3, 12]))  # A2345
    )
    vec[8] = 1.0 if is_straight else 0.0
    vec[9] = 1.0 if len(set(suits)) == 1 else 0.0

    return vec


def encode_combo(combo: HandComboPy, hand13: List[int]) -> np.ndarray:
    """
    将一个 HandComboPy 编码为 COMBO_DIM=74 维特征向量。

    Parameters
    ----------
    combo  : HandComboPy  —— 来自 dfs_enum_combos 的单个候选组合
    hand13 : List[int]    —— 原始 13 张手牌（用于计算全局统计特征）
    """
    vec = np.zeros(COMBO_DIM, dtype=np.float32)

    # ---- 全局 combo 统计 [0:3] ----
    vec[0] = combo.typed_score / _MAX_TYPED_SCORE
    vec[1] = combo.unit_count / 3.0
    vec[2] = combo.loose_count / 13.0

    # ---- 三个 unit 特征 [3:33] ----
    # 按 card_count 分组：先放3张unit，再放5张unit，不足补零
    units_3 = [u for u in combo.units if u.card_count == 3]
    units_5 = [u for u in combo.units if u.card_count == 5]
    ordered_units = (units_3 + units_5)[:3]  # 最多3个

    for i in range(3):
        unit = ordered_units[i] if i < len(ordered_units) else None
        if unit is not None:
            vec[3 + i * 10: 3 + i * 10 + 10] = _unit_features(unit)

    # ---- 散牌统计 [33:52] ----
    loose_rank_cnt = np.zeros(13, dtype=np.float32)
    loose_suit_cnt = np.zeros(4, dtype=np.float32)
    loose_max_rank = 0
    loose_pair_cnt = 0

    for c in combo.loose_cards:
        r = card_rank(c)
        s = card_suit(c)
        loose_rank_cnt[r] += 1
        loose_suit_cnt[s] += 1
        loose_max_rank = max(loose_max_rank, r)

    if combo.loose_count > 0:
        max_freq = max(loose_rank_cnt.max(), 1.0)
        vec[33:46] = loose_rank_cnt / max_freq        # [33:46] 点数分布
        vec[46:50] = loose_suit_cnt / max(combo.loose_count, 1)  # [46:50] 花色分布
        vec[50] = loose_max_rank / 12.0               # [50] 最高点数
        loose_pair_cnt = int((loose_rank_cnt >= 2).sum())
        vec[51] = loose_pair_cnt / 6.0                # [51] 对子数

    # ---- 全局手牌统计 [52:74] ----
    hand_rank_cnt = np.zeros(13, dtype=np.float32)
    hand_suit_cnt = np.zeros(4, dtype=np.float32)
    for c in hand13:
        hand_rank_cnt[card_rank(c)] += 1
        hand_suit_cnt[card_suit(c)] += 1

    vec[52:65] = hand_rank_cnt / 4.0    # [52:65] 点数分布（最多4张同点）
    vec[65:69] = hand_suit_cnt / 13.0   # [65:69] 花色分布

    # [69:74] 全局牌型标志
    vec[69] = 1.0 if (hand_rank_cnt >= 3).any() else 0.0   # 三条
    vec[70] = 1.0 if (hand_rank_cnt >= 4).any() else 0.0   # 四条

    # 顺子：至少有5个连续点数（简单扫描）
    has_straight = False
    for start in range(9):  # 0~8
        if all(hand_rank_cnt[start + j] >= 1 for j in range(5)):
            has_straight = True
            break
    if not has_straight and (hand_rank_cnt[12] >= 1
                              and all(hand_rank_cnt[j] >= 1 for j in range(4))):
        has_straight = True
    vec[71] = 1.0 if has_straight else 0.0

    # 同花：某花色 >= 5 张
    vec[72] = 1.0 if (hand_suit_cnt >= 5).any() else 0.0

    # 同花顺：粗略判断（有同花且有顺子）
    vec[73] = 1.0 if (vec[71] > 0 and vec[72] > 0) else 0.0

    return vec


def encode_batch_combos(
    dfs_result: DFSCandResultPy,
    hand13: List[int],
) -> tuple:
    """
    将 DFS 结果编码为模型批量输入。

    Returns
    -------
    combo_features : np.ndarray  shape (MAX_COMBOS, COMBO_DIM)
    combo_mask     : np.ndarray  shape (MAX_COMBOS,)  float32
    valid_count    : int         实际有效 combo 数量
    """
    combo_features = np.zeros((MAX_COMBOS, COMBO_DIM), dtype=np.float32)
    combo_mask = np.zeros(MAX_COMBOS, dtype=np.float32)

    valid_count = min(dfs_result.combo_count, MAX_COMBOS)
    for i in range(valid_count):
        combo_features[i] = encode_combo(dfs_result.combos[i], hand13)
        combo_mask[i] = 1.0

    return combo_features, combo_mask, valid_count


# ============================================================
# 5.  aggression 相关辅助指标
# ============================================================

def attack_potential(combo: HandComboPy) -> float:
    """
    计算该 combo 的"进攻潜力"，用于 aggression > 0 时的加成。

    逻辑：
      - 头墩(3张unit)强度越高，打枪概率越高
      - 高分牌型（铁支/同花顺）数量越多越好
    返回 [0, 1] 的归一化值。
    """
    score = 0.0
    for unit in combo.units:
        r = unit.result.rank_order
        # 头墩强度权重更高（打枪必须头墩赢）
        if unit.card_count == 3:
            score += r * 2.0   # 头墩三条=4×2=8，对子=2×2=4
        else:
            score += r * 1.0
    # 归一化：最高可能分数约为 3条头(8) + 同花顺尾(9) + 同花顺中(9) = 26
    return min(score / 26.0, 1.0)


def defense_stability(combo: HandComboPy) -> float:
    """
    计算该 combo 的"防守稳定性"，用于 aggression < 0 时的加成。

    逻辑：
      - typed_score 越高整体越稳
      - 散牌越少越好（减少被打枪风险）
      - 有两个5张有牌型单元说明中尾墩较强
    返回 [0, 1] 的归一化值。
    """
    typed_norm = min(combo.typed_score / _MAX_TYPED_SCORE, 1.0)
    loose_penalty = combo.loose_count / 13.0
    five_units = sum(1 for u in combo.units if u.card_count == 5)
    unit_bonus = five_units / 2.0

    stability = typed_norm * 0.5 + (1.0 - loose_penalty) * 0.3 + unit_bonus * 0.2
    return float(np.clip(stability, 0.0, 1.0))
