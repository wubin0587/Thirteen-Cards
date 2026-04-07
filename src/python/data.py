"""
data.py
-------
数据生成与加载层。

职责：
  - 蒙特卡洛模拟计算每个 combo 的期望得分（作为训练标签）
  - 生成 (hand_tokens, combo_features, combo_mask, score_labels) 四元组
  - 封装 PyTorch Dataset / DataLoader
  - 将生成的数据集缓存到磁盘（.npz），避免每次重新跑模拟
  - 不定义模型，不做模型推理

公开接口：
  generate_dataset(n_hands, mc_samples, save_path) → 生成并缓存数据集
  load_dataset(path)                               → ThirteenCardsDataset
  ThirteenCardsDataset                             → PyTorch Dataset
  get_dataloader(dataset, batch_size, shuffle)     → DataLoader

标签设计：
  对每个 combo，计算"在当前手牌下选择该 combo，对战 N 个随机对手时的期望净得分"。
  由于十三水理牌阶段对手手牌不可见，期望分 = 对随机对手的平均胜负分差。
  标签归一化为 softmax 目标分布（温度=1 的软标签），而非 one-hot。
"""

from __future__ import annotations

import os
import random
import logging
from typing import Tuple, Optional

import numpy as np
import torch
from torch.utils.data import Dataset, DataLoader

from input import (
    py_dfs_enum_combos,
    py_search_pattern,
    DFSCandResultPy,
    HandComboPy,
    card_rank,
    deck_single,
    deck_double,
)
from features import (
    encode_hand,
    encode_batch_combos,
    attack_potential,
    defense_stability,
    MAX_COMBOS,
    CARD_DIM,
    COMBO_DIM,
)

logger = logging.getLogger(__name__)

# ============================================================
# 1.  蒙特卡洛期望分计算
# ============================================================

# 墩位分配的所有合法排列（unit 按 card_count 分槽后的 position 映射）
# 规则：card_count==3 → 必须头墩(0)；card_count==5 → 中墩(1)或尾墩(2)
_POSITION_NAMES = ["head", "middle", "tail"]
_POSITION_SIZES = [3, 5, 5]


def _assign_positions(combo: HandComboPy) -> Optional[Tuple[list, list, list]]:
    """
    为 combo 分配墩位，返回 (head_cards, middle_cards, tail_cards)。

    规则：
      - card_count==3 的 unit → 头墩
      - card_count==5 的两个 unit → 中墩、尾墩（按 rank_order 升序：弱→中，强→尾）
      - 散牌填入剩余墩位（按点数降序）

    若无法形成合法三墩（倒水），返回 None。
    """
    units_3 = [u for u in combo.units if u.card_count == 3]
    units_5 = sorted(
        [u for u in combo.units if u.card_count == 5],
        key=lambda u: u.result.rank_order,
    )

    head_cards   = list(units_3[0].cards[:3]) if units_3 else None
    middle_cards = list(units_5[0].cards[:5]) if len(units_5) >= 1 else None
    tail_cards   = list(units_5[1].cards[:5]) if len(units_5) >= 2 else None

    # 用散牌填入空缺墩位
    loose = list(combo.loose_cards[:combo.loose_count])

    if head_cards is None:
        head_cards = sorted(loose[:3], key=lambda c: card_rank(c), reverse=True)
        loose = loose[3:]
    if middle_cards is None:
        middle_cards = sorted(loose[:5], key=lambda c: card_rank(c), reverse=True)
        loose = loose[5:]
    if tail_cards is None:
        tail_cards = sorted(loose[:5], key=lambda c: card_rank(c), reverse=True)

    # 验证墩位大小
    if len(head_cards) != 3 or len(middle_cards) != 5 or len(tail_cards) != 5:
        return None

    # 验证不倒水
    hr_head   = py_search_pattern(0, head_cards)
    hr_middle = py_search_pattern(1, middle_cards)
    hr_tail   = py_search_pattern(2, tail_cards)

    if not (hr_tail.rank_order >= hr_middle.rank_order >= hr_head.rank_order):
        return None

    return head_cards, middle_cards, tail_cards


def _score_against_opponent(
    my_head, my_mid, my_tail,
    op_head, op_mid, op_tail,
) -> int:
    """
    计算我方相对于一个对手的净分（正=赢，负=输）。

    规则：
      - 三墩各赢得 1 分；赢 2 墩以上额外获得 1 分（打枪）
      - 被对手全赢（0:3）额外罚 1 分（被打枪）
    """
    my_scores  = [py_search_pattern(i, cards) for i, cards in
                  enumerate([my_head, my_mid, my_tail])]
    op_scores  = [py_search_pattern(i, cards) for i, cards in
                  enumerate([op_head, op_mid, op_tail])]

    wins = 0
    for ms, os_ in zip(my_scores, op_scores):
        if ms.rank_order > os_.rank_order:
            wins += 1
        elif ms.rank_order == os_.rank_order:
            # 同牌型比较：用水数作为 tiebreak（粗略）
            if ms.score >= os_.score:
                wins += 1

    if wins >= 2:
        return wins + 1     # 打枪奖励
    elif wins == 0:
        return -(3 + 1)     # 被打枪惩罚
    else:
        return wins - (3 - wins)  # wins - losses


def _monte_carlo_score(
    combo: HandComboPy,
    hand13: list,
    n_players: int = 3,
    n_samples: int = 200,
    use_double_deck: bool = False,
) -> float:
    """
    蒙特卡洛模拟：对该 combo 分配墩位后，与 n_players-1 个随机对手对战，
    返回平均净得分。

    Parameters
    ----------
    combo        : 待评估的候选组合
    hand13       : 我方 13 张牌（用于从剩余牌堆中随机抽对手手牌）
    n_players    : 总玩家数（含我方），3~4 用单副，5~8 用双副
    n_samples    : 蒙特卡洛采样次数
    use_double_deck : 是否用双副牌

    Returns
    -------
    float : 平均净得分（未归一化）
    """
    assignment = _assign_positions(combo)
    if assignment is None:
        return -999.0   # 非法方案，极低分数

    my_head, my_mid, my_tail = assignment
    my_cards_set = set(hand13)

    full_deck = deck_double() if use_double_deck else deck_single()
    remaining = [c for c in full_deck if c not in my_cards_set]

    total_score = 0.0
    opponents = n_players - 1

    for _ in range(n_samples):
        sampled = random.sample(remaining, min(13 * opponents, len(remaining)))
        round_score = 0

        for op_idx in range(opponents):
            op_hand = sampled[op_idx * 13: (op_idx + 1) * 13]
            if len(op_hand) < 13:
                continue

            # 随机分配对手手牌（简单策略：按点数降序填最强方案）
            op_hand_sorted = sorted(op_hand, key=lambda c: card_rank(c), reverse=True)
            op_head  = op_hand_sorted[:3]
            op_tail  = op_hand_sorted[3:8]
            op_mid   = op_hand_sorted[8:13]

            round_score += _score_against_opponent(
                my_head, my_mid, my_tail,
                op_head, op_mid, op_tail,
            )

        total_score += round_score

    return total_score / max(n_samples, 1)


# ============================================================
# 2.  单局数据生成
# ============================================================

def _generate_one_sample(
    n_players: int = 3,
    mc_samples: int = 200,
    max_k: int = 32,
) -> Optional[dict]:
    """
    随机发一手 13 张牌，DFS 枚举候选，蒙特卡洛打标，返回字典。

    Returns None 如果手牌是特殊牌型（直接结算，无需 ranking）。
    """
    use_double = n_players >= 5
    deck = deck_double() if use_double else deck_single()
    hand13 = random.sample(deck, 13)

    try:
        dfs_result = py_dfs_enum_combos(hand13, max_k=max_k)
    except Exception as e:
        logger.warning(f"dfs_enum_combos 失败: {e}")
        return None

    # 特殊牌型跳过（直接报到，无需 ranking）
    if dfs_result.is_special:
        return None

    n_combos = dfs_result.combo_count
    if n_combos < 2:
        return None   # 只有一个候选，无需训练

    # 特征编码
    hand_tokens = encode_hand(hand13)                          # (13, CARD_DIM)
    combo_features, combo_mask, _ = encode_batch_combos(
        dfs_result, hand13
    )  # (MAX_COMBOS, COMBO_DIM), (MAX_COMBOS,)

    # 蒙特卡洛打标
    mc_scores = np.full(MAX_COMBOS, -1e9, dtype=np.float32)
    for i in range(n_combos):
        mc_scores[i] = _monte_carlo_score(
            dfs_result.combos[i],
            hand13,
            n_players=n_players,
            n_samples=mc_samples,
            use_double_deck=use_double,
        )

    # 归一化为软标签：只在有效 combo 上做 softmax（温度=1）
    valid_scores = mc_scores[:n_combos].copy()
    valid_scores -= valid_scores.max()   # 数值稳定
    exp_scores = np.exp(valid_scores)
    soft_labels = np.zeros(MAX_COMBOS, dtype=np.float32)
    soft_labels[:n_combos] = exp_scores / exp_scores.sum()

    # attack / defense 辅助特征
    ap_vec = np.zeros(MAX_COMBOS, dtype=np.float32)
    ds_vec = np.zeros(MAX_COMBOS, dtype=np.float32)
    for i in range(n_combos):
        ap_vec[i] = attack_potential(dfs_result.combos[i])
        ds_vec[i] = defense_stability(dfs_result.combos[i])

    return {
        "hand_tokens":    hand_tokens,    # (13, CARD_DIM)
        "combo_features": combo_features, # (MAX_COMBOS, COMBO_DIM)
        "combo_mask":     combo_mask,     # (MAX_COMBOS,)
        "soft_labels":    soft_labels,    # (MAX_COMBOS,)
        "attack_pot":     ap_vec,         # (MAX_COMBOS,)
        "defense_stab":   ds_vec,         # (MAX_COMBOS,)
        "n_valid":        np.array([n_combos], dtype=np.int32),
    }


# ============================================================
# 3.  数据集生成与缓存
# ============================================================

def generate_dataset(
    n_hands:    int = 50_000,
    mc_samples: int = 200,
    max_k:      int = 32,
    n_players:  int = 3,
    save_path:  str = "src/models/train_data.npz",
    seed:       int = 42,
) -> str:
    """
    生成训练数据集并保存为 .npz 文件。

    Parameters
    ----------
    n_hands    : 生成的手牌局数
    mc_samples : 每个 combo 的蒙特卡洛采样次数（越大越准确，越慢）
    max_k      : DFS 保留的最大候选数
    n_players  : 模拟对战玩家数
    save_path  : 输出路径
    seed       : 随机种子

    Returns
    -------
    str : 保存路径
    """
    random.seed(seed)
    np.random.seed(seed)

    os.makedirs(os.path.dirname(save_path) or ".", exist_ok=True)

    arrays = {
        "hand_tokens":    [],
        "combo_features": [],
        "combo_mask":     [],
        "soft_labels":    [],
        "attack_pot":     [],
        "defense_stab":   [],
        "n_valid":        [],
    }

    generated = 0
    attempts  = 0
    target    = n_hands

    logger.info(f"开始生成 {target} 局训练数据 (mc_samples={mc_samples})...")

    while generated < target:
        attempts += 1
        sample = _generate_one_sample(
            n_players=n_players,
            mc_samples=mc_samples,
            max_k=max_k,
        )
        if sample is None:
            continue

        for k, v in sample.items():
            arrays[k].append(v)
        generated += 1

        if generated % 1000 == 0:
            logger.info(f"  已生成 {generated}/{target} 局 "
                        f"(尝试 {attempts} 次，跳过率 "
                        f"{(attempts-generated)/attempts*100:.1f}%)")

    # 转换为 numpy 数组并保存
    np_arrays = {k: np.stack(v, axis=0) for k, v in arrays.items()}
    np.savez_compressed(save_path, **np_arrays)

    logger.info(f"数据集已保存至 {save_path}，共 {generated} 条样本")
    return save_path


# ============================================================
# 4.  PyTorch Dataset
# ============================================================

class ThirteenCardsDataset(Dataset):
    """
    从 .npz 文件加载训练数据。

    每个样本返回 (hand_tokens, combo_features, combo_mask, soft_labels,
                  attack_pot, defense_stab) 的 torch.Tensor 元组。
    """

    def __init__(self, npz_path: str):
        data = np.load(npz_path)
        self.hand_tokens    = torch.from_numpy(data["hand_tokens"])     # (N,13,17)
        self.combo_features = torch.from_numpy(data["combo_features"])  # (N,K,74)
        self.combo_mask     = torch.from_numpy(data["combo_mask"])      # (N,K)
        self.soft_labels    = torch.from_numpy(data["soft_labels"])     # (N,K)
        self.attack_pot     = torch.from_numpy(data["attack_pot"])      # (N,K)
        self.defense_stab   = torch.from_numpy(data["defense_stab"])    # (N,K)
        self.n_valid        = torch.from_numpy(data["n_valid"])         # (N,1)

        self._len = self.hand_tokens.shape[0]

    def __len__(self) -> int:
        return self._len

    def __getitem__(self, idx: int) -> tuple:
        return (
            self.hand_tokens[idx],
            self.combo_features[idx],
            self.combo_mask[idx],
            self.soft_labels[idx],
            self.attack_pot[idx],
            self.defense_stab[idx],
        )

    def split(self, val_ratio: float = 0.1) -> Tuple["ThirteenCardsDataset", "ThirteenCardsDataset"]:
        """按比例切分训练集 / 验证集（不打乱，保持确定性）。"""
        n = len(self)
        n_val = max(1, int(n * val_ratio))
        n_train = n - n_val

        train_ds = _SliceDataset(self, 0, n_train)
        val_ds   = _SliceDataset(self, n_train, n)
        return train_ds, val_ds


class _SliceDataset(Dataset):
    """内部工具：对 ThirteenCardsDataset 进行切片（避免复制数据）。"""

    def __init__(self, parent: ThirteenCardsDataset, start: int, end: int):
        self._parent = parent
        self._start  = start
        self._end    = end

    def __len__(self) -> int:
        return self._end - self._start

    def __getitem__(self, idx: int) -> tuple:
        return self._parent[self._start + idx]


def load_dataset(path: str) -> ThirteenCardsDataset:
    """从磁盘加载已缓存的数据集。"""
    if not os.path.isfile(path):
        raise FileNotFoundError(
            f"找不到数据集文件: {path}\n"
            "请先运行 generate_dataset() 或 train.py --generate 生成数据。"
        )
    return ThirteenCardsDataset(path)


def get_dataloader(
    dataset: Dataset,
    batch_size: int = 256,
    shuffle: bool = True,
    num_workers: int = 0,
) -> DataLoader:
    """封装 PyTorch DataLoader。"""
    return DataLoader(
        dataset,
        batch_size=batch_size,
        shuffle=shuffle,
        num_workers=num_workers,
        pin_memory=torch.cuda.is_available(),
        drop_last=False,
    )
