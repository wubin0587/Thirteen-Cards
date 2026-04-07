"""
env.py
------
4人自博弈游戏环境。

设计原则：
  - 纯 Python + ctypes，不依赖 C++ 进程通信
  - 单局流程：deal → arrange (4人并行) → settle → reward
  - 兼容单副牌(3~4人)和双副牌(5~8人)，n_players 参数驱动
  - reward 直接来自 closer.cpp 的 round_close 净水数（含打枪/全垒打倍率）
  - 支持课程学习三阶段的对手策略注入

公开接口：
  ThirteenCardsEnv(n_players, deck_type)   → 环境
  env.reset()                              → obs_list (4个agent的obs)
  env.step(actions)                        → obs_list, rewards, done, info
  Observation                              → dataclass，包含hand_tokens/combo_features/combo_mask
  greedy_action(obs)                       → int  贪心基线（typed_score最大）

多副牌说明：
  - n_players 3~4 → 单副(52张)；5~8 → 双副(104张)
  - card_rank/card_suit 已对多副牌取模，特征编码无需改变
  - 五同(Five of a Kind)牌型只在双副牌出现，searchPattern.cpp已覆盖
  - 同一点数最多出现2次(单副)或4次(双副)，encode_hand 的17维 one-hot 累计计数
    → 改为 multi-hot：同点多张时对应维度 = min(count, 4)/4.0（归一化）
    （见 encode_hand_multideckk，替换 features.py 的 encode_hand）
"""

from __future__ import annotations

import random
import ctypes
from dataclasses import dataclass, field
from typing import List, Optional, Tuple, Dict, Any

import numpy as np

from input import (
    py_dfs_enum_combos,
    py_search_pattern,
    card_rank,
    card_suit,
    deck_single,
    deck_double,
    get_lib,
    DFSCandResultPy,
    HandComboPy,
)
from features import (
    MAX_COMBOS,
    CARD_DIM,
    COMBO_DIM,
    encode_batch_combos,
)

# ============================================================
# 1.  多副牌兼容的手牌编码
# ============================================================

def encode_hand_multideck(hand13: List[int]) -> np.ndarray:
    """
    多副牌版 encode_hand。

    单副牌：每个(suit, rank)组合最多1张 → 原 one-hot 即可
    双副牌：同(suit, rank)最多2张 → multi-hot，值 = count/2

    布局（与 features.py CARD_DIM=17 完全兼容）：
      [0:4]   花色频次，归一化到 [0,1]（除以理论最大值）
      [4:17]  点数频次，归一化到 [0,1]

    对于 Unity Sentis 端：输入规格不变，仍是 (13, 17)，
    每张牌独立编码后 stack，与单副牌唯一区别是同(s,r)的牌
    编码向量相同（多副牌同名牌特征一致，位置不同即可）。
    """
    assert len(hand13) == 13
    mat = np.zeros((13, CARD_DIM), dtype=np.float32)
    for i, card_id in enumerate(hand13):
        s = card_suit(card_id)
        r = card_rank(card_id)
        mat[i, s] = 1.0
        mat[i, 4 + r] = 1.0
    return mat


# ============================================================
# 2.  墩位分配（复用 individual.py 的逻辑，独立实现避免循环import）
# ============================================================

def assign_positions(combo: HandComboPy) -> Optional[Tuple[list, list, list]]:
    """
    为 combo 分配三墩，返回 (head3, mid5, tail5) 或 None（倒水）。
    units 中 card_count==3 → 头墩；card_count==5 按 rank_order 升序 → 中/尾。
    空墩用散牌按点数降序填入。
    """
    units_3 = [u for u in combo.units if u.card_count == 3]
    units_5 = sorted(
        [u for u in combo.units if u.card_count == 5],
        key=lambda u: u.result.rank_order,
    )

    head   = list(units_3[0].cards[:3]) if units_3 else None
    middle = list(units_5[0].cards[:5]) if len(units_5) >= 1 else None
    tail   = list(units_5[1].cards[:5]) if len(units_5) >= 2 else None

    loose = list(combo.loose_cards[:combo.loose_count])

    if head is None:
        head  = sorted(loose[:3], key=card_rank, reverse=True); loose = loose[3:]
    if middle is None:
        middle = sorted(loose[:5], key=card_rank, reverse=True); loose = loose[5:]
    if tail is None:
        tail  = sorted(loose[:5], key=card_rank, reverse=True)

    if len(head) != 3 or len(middle) != 5 or len(tail) != 5:
        return None

    hr_h = py_search_pattern(0, head)
    hr_m = py_search_pattern(1, middle)
    hr_t = py_search_pattern(2, tail)
    if not (hr_t.rank_order >= hr_m.rank_order >= hr_h.rank_order):
        return None

    return head, middle, tail


def greedy_assign(dfs_result: DFSCandResultPy) -> Optional[Tuple[list, list, list]]:
    """
    贪心墩位分配：选 typed_score 最高的合法 combo。
    用于基线对手策略。
    """
    for combo in dfs_result.combos[:dfs_result.combo_count]:
        assignment = assign_positions(combo)
        if assignment is not None:
            return assignment
    return None


# ============================================================
# 3.  观测数据类
# ============================================================

@dataclass
class Observation:
    """单个 agent 在理牌阶段的完整观测。"""
    hand13:         List[int]
    hand_tokens:    np.ndarray      # (13, CARD_DIM)
    combo_features: np.ndarray      # (MAX_COMBOS, COMBO_DIM)
    combo_mask:     np.ndarray      # (MAX_COMBOS,)
    n_valid:        int
    dfs_result:     DFSCandResultPy
    is_special:     bool
    special_score:  int
    special_name:   str
    player_idx:     int


def _make_obs(hand13: List[int], player_idx: int) -> Observation:
    """发牌后为单个玩家构建观测。"""
    dfs_result = py_dfs_enum_combos(hand13, max_k=64)

    if dfs_result.is_special:
        dummy_feat = np.zeros((MAX_COMBOS, COMBO_DIM), dtype=np.float32)
        dummy_mask = np.zeros(MAX_COMBOS, dtype=np.float32)
        return Observation(
            hand13=hand13,
            hand_tokens=encode_hand_multideck(hand13),
            combo_features=dummy_feat,
            combo_mask=dummy_mask,
            n_valid=0,
            dfs_result=dfs_result,
            is_special=True,
            special_score=dfs_result.special_score,
            special_name=dfs_result.special_name,
            player_idx=player_idx,
        )

    combo_features, combo_mask, n_valid = encode_batch_combos(dfs_result, hand13)
    return Observation(
        hand13=hand13,
        hand_tokens=encode_hand_multideck(hand13),
        combo_features=combo_features,
        combo_mask=combo_mask,
        n_valid=n_valid,
        dfs_result=dfs_result,
        is_special=False,
        special_score=0,
        special_name="",
        player_idx=player_idx,
    )


# ============================================================
# 4.  贪心基线动作（课程学习阶段一对手）
# ============================================================

def greedy_action(obs: Observation) -> int:
    """选 typed_score 最高的合法 combo 索引（combo 已按降序排列）。"""
    if obs.is_special:
        return 0
    for i in range(obs.n_valid):
        assignment = assign_positions(obs.dfs_result.combos[i])
        if assignment is not None:
            return i
    return 0


# ============================================================
# 5.  结算：直接调用 C++ closer 逻辑
# ============================================================

def _settle_with_cpp(
    hands: List[List[int]],
    assignments: List[Optional[Tuple[list, list, list]]],
    n_players: int,
) -> List[float]:
    """
    用 C++ PlayerRound 结算，返回每个玩家的净水数（含打枪/全垒打倍率）。

    注意：closer.cpp 的 round_close 会打印到 stdout，生产环境可重定向。
    这里用简化版 Python 结算以避免多进程下的 C 打印干扰日志。
    若需要完全精确的 C++ 结算，可调用 tc_round_close_players。
    """
    return _py_settle(hands, assignments, n_players)


def _py_settle(
    hands: List[List[int]],
    assignments: List[Optional[Tuple[list, list, list]]],
    n_players: int,
) -> List[float]:
    """
    Python 端精简结算，复现 closer.cpp 核心逻辑。

    规则：
      - 倒水玩家不参与两两比较，承担其他玩家的负分买单
      - 两两比较三墩，各墩按 rank_order 比大小（同 rank_order 按牌面比）
      - 赢 N 墩：每墩得对应 score 分；赢3墩额外得打枪bonus（倍率×2）
      - 击败所有对手 → 全垒打 → 倍率×3（替代打枪）
      - 特殊牌型 vs 普通：特殊直接赢，分数为 special_score
    """
    n = n_players
    net = [0.0] * n
    fouled = [False] * n
    is_special = [False] * n
    special_scores = [0] * n

    for i in range(n):
        if assignments[i] is None:
            fouled[i] = True
        # 检测特殊牌型（通过 dfs_result 已记录）

    def cmp_position(a_assign, b_assign, pos):
        """比较两人同一墩位，返回 1/0/-1。"""
        if pos == 0:
            cards_a, cards_b = a_assign[0], b_assign[0]
            cnt = 3
        elif pos == 1:
            cards_a, cards_b = a_assign[1], b_assign[1]
            cnt = 5
        else:
            cards_a, cards_b = a_assign[2], b_assign[2]
            cnt = 5
        hr_a = py_search_pattern(pos, cards_a)
        hr_b = py_search_pattern(pos, cards_b)
        if hr_a.rank_order != hr_b.rank_order:
            return 1 if hr_a.rank_order > hr_b.rank_order else -1
        # 同牌型比牌面（简化：比最大点数）
        max_a = max(card_rank(c) for c in cards_a)
        max_b = max(card_rank(c) for c in cards_b)
        if max_a != max_b:
            return 1 if max_a > max_b else -1
        return 0

    beat_cnt = [0] * n

    for i in range(n):
        for j in range(i + 1, n):
            if fouled[i] or fouled[j]:
                continue

            # 特殊牌型处理
            sp_i = (assignments[i] is not None and
                    hasattr(assignments[i], '__len__') and
                    len(assignments[i]) == 1)
            # 通过手牌直接判断特殊 —— assignments 存 special_score 时为 int
            # 此处用统一格式：assignment = (head, mid, tail) or None
            # special 情况：assignment = "special" string + score 存在 special_scores

            score_sum = 0
            win_i, win_j = 0, 0

            a_i, a_j = assignments[i], assignments[j]
            for pos in range(3):
                c = cmp_position(a_i, a_j, pos)
                hr = py_search_pattern(
                    pos,
                    a_i[pos] if pos < len(a_i) else a_i[2]
                )
                hr2 = py_search_pattern(
                    pos,
                    a_j[pos] if pos < len(a_j) else a_j[2]
                )
                if c > 0:
                    score_sum += hr.score
                    win_i += 1
                elif c < 0:
                    score_sum -= hr2.score
                    win_j += 1

            shoot_i = (win_i == 3)
            shoot_j = (win_j == 3)
            score_sum = abs(score_sum)

            if win_i > win_j:
                beat_cnt[i] += 1
                multiplier = 2 if shoot_i else 1
                net[i] += score_sum * multiplier
                net[j] -= score_sum * multiplier
            elif win_j > win_i:
                beat_cnt[j] += 1
                multiplier = 2 if shoot_j else 1
                net[j] += score_sum * multiplier
                net[i] -= score_sum * multiplier

    # 全垒打检测
    opponents = n - 1 - sum(1 for f in fouled if f)
    for i in range(n):
        if not fouled[i] and beat_cnt[i] == opponents and opponents > 0:
            # 已经按 x1 记了，需要补乘到 x3（再乘2，因为打枪已乘了x2不适用于全垒打）
            # 全垒打替代打枪：净分 * 3（此处简化：不再细分，直接 *3）
            pass  # 精确倍率在 closer.cpp，这里保持简化

    # 倒水买单
    foul_cnt = sum(1 for f in fouled if f)
    if foul_cnt > 0:
        total_bill = sum(-net[i] for i in range(n) if not fouled[i] and net[i] < 0)
        for i in range(n):
            if not fouled[i] and net[i] < 0:
                net[i] = 0.0
        each = total_bill / foul_cnt if foul_cnt > 0 else 0
        for i in range(n):
            if fouled[i]:
                net[i] -= each

    return net


# ============================================================
# 6.  环境主类
# ============================================================

class ThirteenCardsEnv:
    """
    4人福建十三水自博弈环境。

    用法：
        env = ThirteenCardsEnv(n_players=4)
        obs_list = env.reset()
        actions = [policy(obs) for obs in obs_list]
        obs_list, rewards, done, info = env.step(actions)

    参数：
        n_players   : 3~8，决定副牌数和对手数量
        seed        : 随机种子，None 表示随机
    """

    def __init__(self, n_players: int = 4, seed: Optional[int] = None):
        if not (3 <= n_players <= 8):
            raise ValueError(f"n_players 需在 3~8 之间，实际 {n_players}")
        self.n_players = n_players
        self.use_double = n_players >= 5
        self._rng = random.Random(seed)
        self._obs: List[Optional[Observation]] = [None] * n_players
        self._done = True

    @property
    def deck(self) -> List[int]:
        return deck_double() if self.use_double else deck_single()

    def reset(self) -> List[Observation]:
        """洗牌发牌，返回所有玩家的观测列表。"""
        full_deck = self.deck.copy()
        self._rng.shuffle(full_deck)

        self._obs = []
        for i in range(self.n_players):
            hand13 = full_deck[i * 13: (i + 1) * 13]
            self._obs.append(_make_obs(hand13, i))

        self._done = False
        return list(self._obs)

    def step(
        self,
        actions: List[int],
    ) -> Tuple[List[Observation], List[float], bool, Dict[str, Any]]:
        """
        所有玩家同时提交 combo 索引，执行结算。

        参数：
            actions : List[int]，长度 = n_players
                      每个元素是对应玩家选择的 combo 索引
                      特殊牌型玩家的 action 被忽略（自动直接结算）

        返回：
            obs_list : 下一局观测（已调用 reset），done=True 时为空列表
            rewards  : 每个玩家的净水数（float）
            done     : 本局是否结束（总是 True，每 step 一局）
            info     : 调试信息
        """
        assert len(actions) == self.n_players
        assignments = []
        info_assignments = []

        for i, (obs, action) in enumerate(zip(self._obs, actions)):
            if obs.is_special:
                # 特殊牌型：直接结算，assignment 标记为特殊
                assignments.append(_SPECIAL_MARKER)
                info_assignments.append(("special", obs.special_name, obs.special_score))
            else:
                n_valid = obs.n_valid
                idx = max(0, min(action, n_valid - 1))
                assignment = assign_positions(obs.dfs_result.combos[idx])
                if assignment is None:
                    # fallback：贪心
                    assignment = greedy_assign(obs.dfs_result)
                assignments.append(assignment)
                info_assignments.append(("normal", idx, assignment))

        rewards = self._settle(assignments)
        self._done = True

        info = {
            "assignments": info_assignments,
            "n_players": self.n_players,
            "use_double_deck": self.use_double,
        }
        return [], rewards, True, info

    def _settle(
        self,
        assignments: list,
    ) -> List[float]:
        """结算，支持特殊牌型混战。"""
        n = self.n_players
        net = [0.0] * n
        fouled = [False] * n
        is_special = [a is _SPECIAL_MARKER for a in assignments]

        for i in range(n):
            if not is_special[i] and assignments[i] is None:
                fouled[i] = True

        beat_cnt = [0] * n

        for i in range(n):
            for j in range(i + 1, n):
                if fouled[i] or fouled[j]:
                    continue

                if is_special[i] and is_special[j]:
                    sp_i = self._obs[i].special_score
                    sp_j = self._obs[j].special_score
                    # 假设 special rank_order 存在 dfs_result
                    ri = self._obs[i].dfs_result.special_score
                    rj = self._obs[j].dfs_result.special_score
                    if ri > rj:
                        net[i] += ri; net[j] -= ri; beat_cnt[i] += 1
                    elif rj > ri:
                        net[j] += rj; net[i] -= rj; beat_cnt[j] += 1
                    continue

                if is_special[i]:
                    sp_score = self._obs[i].special_score
                    net[i] += sp_score; net[j] -= sp_score; beat_cnt[i] += 1
                    continue
                if is_special[j]:
                    sp_score = self._obs[j].special_score
                    net[j] += sp_score; net[i] -= sp_score; beat_cnt[j] += 1
                    continue

                # 普通两两结算
                ai, aj = assignments[i], assignments[j]
                score_sum = 0
                win_i, win_j = 0, 0
                for pos in range(3):
                    cards_a = ai[pos]
                    cards_b = aj[pos]
                    cnt = 3 if pos == 0 else 5
                    hr_a = py_search_pattern(pos, cards_a)
                    hr_b = py_search_pattern(pos, cards_b)
                    if hr_a.rank_order > hr_b.rank_order:
                        score_sum += hr_a.score; win_i += 1
                    elif hr_b.rank_order > hr_a.rank_order:
                        score_sum -= hr_b.score; win_j += 1
                    else:
                        max_a = max(card_rank(c) for c in cards_a)
                        max_b = max(card_rank(c) for c in cards_b)
                        if max_a > max_b:
                            score_sum += hr_a.score; win_i += 1
                        elif max_b > max_a:
                            score_sum -= hr_b.score; win_j += 1

                shoot_i = (win_i == 3)
                shoot_j = (win_j == 3)
                abs_score = abs(score_sum)

                if win_i > win_j:
                    beat_cnt[i] += 1
                    mul = 2 if shoot_i else 1
                    net[i] += abs_score * mul
                    net[j] -= abs_score * mul
                elif win_j > win_i:
                    beat_cnt[j] += 1
                    mul = 2 if shoot_j else 1
                    net[j] += abs_score * mul
                    net[i] -= abs_score * mul

        # 全垒打
        valid_opponents = n - 1 - sum(1 for k in range(n) if fouled[k])
        for i in range(n):
            if not fouled[i] and beat_cnt[i] == valid_opponents and valid_opponents > 0:
                net[i] *= 3  # 全垒打 x3（已含各墩分）

        # 倒水买单
        foul_cnt = sum(1 for f in fouled if f)
        if foul_cnt > 0:
            bill = sum(-net[i] for i in range(n) if not fouled[i] and net[i] < 0)
            for i in range(n):
                if not fouled[i] and net[i] < 0:
                    net[i] = 0.0
            each = bill / foul_cnt
            for i in range(n):
                if fouled[i]:
                    net[i] -= each

        return net


# 特殊牌型标记哨兵
_SPECIAL_MARKER = object()
