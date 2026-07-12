"""
individual.py
-------------
个性化推理与调试入口。

职责：
  - 接受 temperature 和 aggression 参数，执行单局推理
  - 人类可读的方案可视化（三墩展示、牌型名称、得分）
  - 难度预设快捷调用
  - 交互式调试模式（命令行循环）
  - 不训练模型，不写 src/models/ 目录

用法：
  # 随机发牌，使用默认参数推理
  python individual.py

  # 指定难度预设
  python individual.py --difficulty hard

  # 手动调参
  python individual.py --temperature 0.8 --aggression 0.4

  # 指定手牌（空格分隔的牌号）
  python individual.py --hand "0 5 10 15 20 25 30 35 40 45 50 3 8"

  # 显示全部候选方案的排名
  python individual.py --show_all --top_k 5

  # 交互式模式
  python individual.py --interactive
"""

from __future__ import annotations

import argparse
import os
import random
import sys
from dataclasses import dataclass
from typing import List, Optional, Tuple

import numpy as np
import torch

from input import (
    py_dfs_enum_combos,
    py_search_pattern,
    DFSCandResultPy,
    HandComboPy,
    hand_to_names,
    card_rank,
    deck_single,
    deck_double,
    load_lib,
)
from features import (
    encode_hand,
    encode_batch_combos,
    attack_potential,
    defense_stability,
    MAX_COMBOS,
)
from models import (
    ModelConfig,
    TransformerRanker,
    inference,
    get_preset,
    DIFFICULTY_PRESETS,
)

# ============================================================
# 路径常量
# ============================================================

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.join(_SCRIPT_DIR, "models")
CKPT_PATH  = os.path.join(MODELS_DIR, "thirteen_cards_ranker.pt")


# ============================================================
# 1.  模型加载
# ============================================================

def load_model(
    ckpt_path: str = CKPT_PATH,
    device:    Optional[torch.device] = None,
) -> Tuple[TransformerRanker, ModelConfig]:
    """
    从 checkpoint 加载模型。

    Returns
    -------
    (model, cfg)
    """
    if device is None:
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    if not os.path.isfile(ckpt_path):
        raise FileNotFoundError(
            f"找不到模型文件: {ckpt_path}\n"
            "请先运行 python train.py --all 训练并导出模型。"
        )

    ckpt = torch.load(ckpt_path, map_location=device)
    cfg_dict = ckpt.get("cfg", {})
    cfg = ModelConfig(**{
        k: cfg_dict[k]
        for k in ModelConfig.__dataclass_fields__
        if k in cfg_dict
    })
    model = TransformerRanker(cfg).to(device)
    model.load_state_dict(ckpt["model_state"])
    model.eval()
    return model, cfg


# ============================================================
# 2.  墩位分配辅助（与 data.py 保持一致逻辑）
# ============================================================

def assign_positions(combo: HandComboPy) -> Optional[Tuple[list, list, list]]:
    """
    为 combo 分配墩位，返回 (head_cards, middle_cards, tail_cards)。
    若非法（倒水）返回 None。
    """
    units_3 = [u for u in combo.units if u.card_count == 3]
    units_5 = sorted(
        [u for u in combo.units if u.card_count == 5],
        key=lambda u: u.result.rank_order,
    )

    head_cards   = list(units_3[0].cards[:3]) if units_3 else None
    middle_cards = list(units_5[0].cards[:5]) if len(units_5) >= 1 else None
    tail_cards   = list(units_5[1].cards[:5]) if len(units_5) >= 2 else None

    loose = list(combo.loose_cards[:combo.loose_count])

    if head_cards is None:
        head_cards   = sorted(loose[:3], key=lambda c: card_rank(c), reverse=True)
        loose        = loose[3:]
    if middle_cards is None:
        middle_cards = sorted(loose[:5], key=lambda c: card_rank(c), reverse=True)
        loose        = loose[5:]
    if tail_cards is None:
        tail_cards   = sorted(loose[:5], key=lambda c: card_rank(c), reverse=True)

    if len(head_cards) != 3 or len(middle_cards) != 5 or len(tail_cards) != 5:
        return None

    hr_h = py_search_pattern(0, head_cards)
    hr_m = py_search_pattern(1, middle_cards)
    hr_t = py_search_pattern(2, tail_cards)

    if not (hr_t.rank_order >= hr_m.rank_order >= hr_h.rank_order):
        return None

    return head_cards, middle_cards, tail_cards


# ============================================================
# 3.  结果数据类
# ============================================================

@dataclass
class InferenceResult:
    """单局推理的完整输出。"""
    hand13:         List[int]
    chosen_idx:     int
    combo:          HandComboPy
    head_cards:     List[int]
    middle_cards:   List[int]
    tail_cards:     List[int]
    head_name:      str
    middle_name:    str
    tail_name:      str
    head_score:     int
    middle_score:   int
    tail_score:     int
    total_score:    int
    typed_score:    int
    attack_pot:     float
    defense_stab:   float
    temperature:    float
    aggression:     float
    n_candidates:   int
    is_special:     bool
    special_name:   str
    special_score:  int


# ============================================================
# 4.  核心推理函数
# ============================================================

def run_inference(
    hand13:      List[int],
    model:       TransformerRanker,
    temperature: float = 1.0,
    aggression:  float = 0.0,
    max_k:       int   = 32,
    device:      Optional[torch.device] = None,
) -> InferenceResult:
    """
    对一手 13 张牌执行完整推理，返回 InferenceResult。

    Parameters
    ----------
    hand13      : 13张牌的牌号列表
    model       : 已加载的 TransformerRanker
    temperature : 采样温度 (0.1~5.0)
    aggression  : 攻守倾向 (-1.0~1.0)
    max_k       : DFS 最大候选数
    device      : 推理设备
    """
    if device is None:
        device = next(model.parameters()).device

    # ---- DFS 枚举 ----
    dfs_result = py_dfs_enum_combos(hand13, max_k=max_k)

    # ---- 特殊牌型直接返回 ----
    if dfs_result.is_special:
        return InferenceResult(
            hand13=hand13, chosen_idx=-1, combo=None,
            head_cards=[], middle_cards=[], tail_cards=[],
            head_name="", middle_name="", tail_name="",
            head_score=0, middle_score=0, tail_score=0,
            total_score=dfs_result.special_score,
            typed_score=dfs_result.special_score,
            attack_pot=0.0, defense_stab=0.0,
            temperature=temperature, aggression=aggression,
            n_candidates=0,
            is_special=True,
            special_name=dfs_result.special_name,
            special_score=dfs_result.special_score,
        )

    n_valid = dfs_result.combo_count
    if n_valid == 0:
        raise ValueError("DFS 枚举结果为空，手牌可能有误")

    # ---- 特征编码 ----
    hand_tokens_np, combo_features_np, combo_mask_np, _ = (
        encode_hand(hand13),
        *encode_batch_combos(dfs_result, hand13),
    )

    hand_tokens    = torch.from_numpy(hand_tokens_np).unsqueeze(0).to(device)
    combo_features = torch.from_numpy(combo_features_np).unsqueeze(0).to(device)
    combo_mask     = torch.from_numpy(combo_mask_np).unsqueeze(0).to(device)

    # ---- attack / defense 向量 ----
    ap_vec = np.array([attack_potential(dfs_result.combos[i]) for i in range(n_valid)]
                      + [0.0] * (MAX_COMBOS - n_valid), dtype=np.float32)
    ds_vec = np.array([defense_stability(dfs_result.combos[i]) for i in range(n_valid)]
                      + [0.0] * (MAX_COMBOS - n_valid), dtype=np.float32)

    ap_tensor = torch.from_numpy(ap_vec).unsqueeze(0).to(device)
    ds_tensor = torch.from_numpy(ds_vec).unsqueeze(0).to(device)

    # ---- 模型推理 ----
    chosen_idx = inference(
        model          = model,
        hand_tokens    = hand_tokens,
        combo_features = combo_features,
        combo_mask     = combo_mask,
        temperature    = temperature,
        aggression     = aggression,
        attack_potentials    = ap_tensor,
        defense_stabilities  = ds_tensor,
        deterministic  = (temperature < 0.05),
    )
    chosen_idx = min(chosen_idx, n_valid - 1)

    # ---- 墩位分配 ----
    combo = dfs_result.combos[chosen_idx]
    assignment = assign_positions(combo)

    if assignment is None:
        # fallback：用 typed_score 最高的合法方案
        for i in range(n_valid):
            assignment = assign_positions(dfs_result.combos[i])
            if assignment is not None:
                combo = dfs_result.combos[i]
                chosen_idx = i
                break
        if assignment is None:
            raise RuntimeError("所有候选方案均非法（倒水），请检查 DFS 逻辑")

    head_cards, middle_cards, tail_cards = assignment

    hr_h = py_search_pattern(0, head_cards)
    hr_m = py_search_pattern(1, middle_cards)
    hr_t = py_search_pattern(2, tail_cards)

    return InferenceResult(
        hand13       = hand13,
        chosen_idx   = chosen_idx,
        combo        = combo,
        head_cards   = head_cards,
        middle_cards = middle_cards,
        tail_cards   = tail_cards,
        head_name    = hr_h.hand_name,
        middle_name  = hr_m.hand_name,
        tail_name    = hr_t.hand_name,
        head_score   = hr_h.score,
        middle_score = hr_m.score,
        tail_score   = hr_t.score,
        total_score  = hr_h.score + hr_m.score + hr_t.score,
        typed_score  = combo.typed_score,
        attack_pot   = float(ap_vec[chosen_idx]),
        defense_stab = float(ds_vec[chosen_idx]),
        temperature  = temperature,
        aggression   = aggression,
        n_candidates = n_valid,
        is_special   = False,
        special_name = "",
        special_score= 0,
    )


# ============================================================
# 5.  可视化
# ============================================================

_SEP = "─" * 52


def _card_row(cards: List[int], zh: bool = True) -> str:
    return "  ".join(hand_to_names(cards, zh=zh))


def print_result(
    result:   InferenceResult,
    dfs_result: Optional[DFSCandResultPy] = None,
    show_all: bool = False,
    top_k:    int  = 5,
    zh:       bool = True,
) -> None:
    """将推理结果以可读格式打印到控制台。"""

    print(f"\n{_SEP}")
    print(f"  🃏 手牌：{_card_row(result.hand13, zh)}")
    print(f"  温度 T={result.temperature:.2f}  激进度 A={result.aggression:+.2f}  "
          f"候选数 {result.n_candidates}")
    print(_SEP)

    if result.is_special:
        print(f"  🎆 特殊牌型：{result.special_name}")
        print(f"  💰 直接得分：{result.special_score} 水")
        print(_SEP)
        return

    print(f"  🔝 头墩（3张）  {_card_row(result.head_cards, zh)}")
    print(f"     牌型：{result.head_name:<20} 得分：{result.head_score} 水")
    print()
    print(f"  🎯 中墩（5张）  {_card_row(result.middle_cards, zh)}")
    print(f"     牌型：{result.middle_name:<20} 得分：{result.middle_score} 水")
    print()
    print(f"  🏆 尾墩（5张）  {_card_row(result.tail_cards, zh)}")
    print(f"     牌型：{result.tail_name:<20} 得分：{result.tail_score} 水")
    print()
    print(f"  💰 合计得分：{result.total_score} 水  "
          f"（有牌型得分 {result.typed_score} 水）")
    print(f"  ⚔  进攻潜力：{result.attack_pot:.2f}  "
          f"🛡 防守稳定：{result.defense_stab:.2f}")
    print(_SEP)

    # 显示全部候选方案排名
    if show_all and dfs_result is not None:
        _print_all_candidates(dfs_result, result.hand13, top_k, zh)


def _print_all_candidates(
    dfs_result: DFSCandResultPy,
    hand13:     List[int],
    top_k:      int  = 5,
    zh:         bool = True,
) -> None:
    """打印 Top-K 候选方案的简要信息。"""
    n = min(top_k, dfs_result.combo_count)
    print(f"\n  Top-{n} 候选方案（按 typed_score 降序）：")
    for i in range(n):
        c = dfs_result.combos[i]
        ap = attack_potential(c)
        ds = defense_stability(c)
        unit_strs = []
        for u in c.units:
            names = hand_to_names(u.cards[:u.card_count], zh)
            unit_strs.append(f"[{'  '.join(names)} | {u.result.hand_name}]")
        loose_str = hand_to_names(c.loose_cards[:c.loose_count], zh)
        print(f"  #{i+1:>2}  typed={c.typed_score:>3}  "
              f"ap={ap:.2f} ds={ds:.2f}")
        for s in unit_strs:
            print(f"       {s}")
        if loose_str:
            print(f"       散牌: {'  '.join(loose_str)}")
    print(_SEP)


# ============================================================
# 6.  参数扫描（调试用）
# ============================================================

def sweep_temperature(
    hand13:      List[int],
    model:       TransformerRanker,
    temperatures: List[float] = [0.1, 0.5, 1.0, 2.0, 3.0],
    aggression:   float = 0.0,
    n_repeats:    int   = 5,
    device:       Optional[torch.device] = None,
) -> None:
    """
    对同一手牌，在不同温度下重复推理，观察方案多样性。
    用于验证 temperature 参数的效果。
    """
    print(f"\n{'='*52}")
    print(f"温度扫描  手牌: {hand_to_names(hand13, zh=True)}")
    print(f"固定 aggression={aggression:+.2f}，每档温度重复 {n_repeats} 次")
    print("="*52)

    for T in temperatures:
        chosen_idxs = []
        total_scores = []
        for _ in range(n_repeats):
            res = run_inference(hand13, model, temperature=T,
                                aggression=aggression, device=device)
            chosen_idxs.append(res.chosen_idx)
            total_scores.append(res.total_score)

        unique = len(set(chosen_idxs))
        avg_score = sum(total_scores) / len(total_scores)
        print(f"  T={T:.1f}  方案多样性={unique}/{n_repeats}  "
              f"平均得分={avg_score:.1f}  "
              f"选择: {chosen_idxs}")


def sweep_aggression(
    hand13:      List[int],
    model:       TransformerRanker,
    aggressions:  List[float] = [-1.0, -0.5, 0.0, 0.5, 1.0],
    temperature:  float = 0.1,   # 低温使结果确定，便于观察 aggression 效果
    device:       Optional[torch.device] = None,
) -> None:
    """
    对同一手牌，在不同 aggression 下观察选牌倾向变化。
    """
    print(f"\n{'='*52}")
    print(f"激进度扫描  手牌: {hand_to_names(hand13, zh=True)}")
    print(f"固定 temperature={temperature:.2f}（确定性推理）")
    print("="*52)

    for A in aggressions:
        res = run_inference(hand13, model, temperature=temperature,
                            aggression=A, device=device)
        label = "激进" if A > 0.2 else ("保守" if A < -0.2 else "均衡")
        print(f"  A={A:+.1f} [{label}]  "
              f"头:{res.head_name:<15} 中:{res.middle_name:<15} "
              f"尾:{res.tail_name:<15}  "
              f"进攻潜力={res.attack_pot:.2f}")


# ============================================================
# 7.  交互式调试模式
# ============================================================

def interactive_mode(
    model:  TransformerRanker,
    device: Optional[torch.device] = None,
) -> None:
    """
    命令行交互式循环，支持：
      r            随机发牌
      h <ids...>   指定手牌
      t <float>    设置温度
      a <float>    设置激进度
      d <preset>   设置难度预设
      s            温度扫描
      g            激进度扫描
      q            退出
    """
    print("\n🃏 福建十三水 AI 调试模式")
    print("命令: r=随机发牌  h=指定手牌  t=温度  a=激进度  d=难度  s=温度扫描  g=激进度扫描  q=退出")

    temperature = 1.0
    aggression  = 0.0
    hand13: Optional[List[int]] = None
    dfs_result: Optional[DFSCandResultPy] = None

    while True:
        try:
            raw = input("\n> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n退出")
            break

        if not raw:
            continue

        parts = raw.split()
        cmd   = parts[0].lower()

        if cmd == "q":
            print("退出")
            break

        elif cmd == "r":
            deck   = deck_single()
            hand13 = random.sample(deck, 13)
            print(f"随机手牌: {hand_to_names(hand13, zh=True)}")
            dfs_result = py_dfs_enum_combos(hand13, max_k=32)
            res = run_inference(hand13, model, temperature, aggression, device=device)
            print_result(res, dfs_result, show_all=False)

        elif cmd == "h":
            if len(parts) < 14:
                print("格式: h <13个空格分隔的牌号>")
                continue
            try:
                hand13 = [int(x) for x in parts[1:14]]
                print(f"手牌: {hand_to_names(hand13, zh=True)}")
                dfs_result = py_dfs_enum_combos(hand13, max_k=32)
                res = run_inference(hand13, model, temperature, aggression, device=device)
                print_result(res, dfs_result, show_all=False)
            except ValueError:
                print("牌号必须是整数")

        elif cmd == "t":
            if len(parts) < 2:
                print(f"当前温度: {temperature}")
                continue
            try:
                temperature = float(parts[1])
                temperature = max(0.01, min(10.0, temperature))
                print(f"温度已设为 {temperature:.2f}")
                if hand13:
                    res = run_inference(hand13, model, temperature, aggression, device=device)
                    print_result(res, dfs_result)
            except ValueError:
                print("温度必须是浮点数")

        elif cmd == "a":
            if len(parts) < 2:
                print(f"当前激进度: {aggression:+.2f}")
                continue
            try:
                aggression = float(parts[1])
                aggression = max(-1.0, min(1.0, aggression))
                print(f"激进度已设为 {aggression:+.2f}")
                if hand13:
                    res = run_inference(hand13, model, temperature, aggression, device=device)
                    print_result(res, dfs_result)
            except ValueError:
                print("激进度必须是浮点数")

        elif cmd == "d":
            if len(parts) < 2:
                print(f"可用预设: {list(DIFFICULTY_PRESETS.keys())}")
                continue
            try:
                preset = get_preset(parts[1])
                temperature = preset["temperature"]
                aggression  = preset["aggression"]
                print(f"难度预设 '{parts[1]}': T={temperature:.2f}, A={aggression:+.2f}")
                if hand13:
                    res = run_inference(hand13, model, temperature, aggression, device=device)
                    print_result(res, dfs_result)
            except ValueError as e:
                print(e)

        elif cmd == "s":
            if hand13 is None:
                print("请先发牌 (r 或 h)")
                continue
            sweep_temperature(hand13, model, aggression=aggression, device=device)

        elif cmd == "g":
            if hand13 is None:
                print("请先发牌 (r 或 h)")
                continue
            sweep_aggression(hand13, model, device=device)

        else:
            print(f"未知命令: {cmd}")


# ============================================================
# 8.  CLI 入口
# ============================================================

def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="福建十三水 AI 个性化推理调试")

    parser.add_argument("--ckpt",        type=str,   default=CKPT_PATH)
    parser.add_argument("--temperature", type=float, default=1.0)
    parser.add_argument("--aggression",  type=float, default=0.0)
    parser.add_argument("--difficulty",  type=str,   default=None,
                        choices=list(DIFFICULTY_PRESETS.keys()))
    parser.add_argument("--hand",        type=str,   default=None,
                        help="空格分隔的13个牌号，如 '0 5 10 15 20 25 30 35 40 45 50 3 8'")
    parser.add_argument("--max_k",       type=int,   default=32)
    parser.add_argument("--show_all",    action="store_true")
    parser.add_argument("--top_k",       type=int,   default=5)
    parser.add_argument("--sweep_t",     action="store_true", help="温度扫描")
    parser.add_argument("--sweep_a",     action="store_true", help="激进度扫描")
    parser.add_argument("--interactive", action="store_true", help="交互式模式")
    parser.add_argument("--n_repeats",   type=int,   default=5)

    return parser.parse_args()


def main() -> None:
    args = _parse_args()

    # 加载库和模型
    try:
        load_lib()
    except FileNotFoundError as e:
        print(f"[警告] {e}")
        print("C++ 库未加载，部分功能不可用。")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    try:
        model, cfg = load_model(args.ckpt, device)
        print(f"模型已加载 ({model.count_parameters():,} 参数，设备: {device})")
    except FileNotFoundError as e:
        print(f"[错误] {e}")
        sys.exit(1)

    # 难度预设覆盖
    temperature = args.temperature
    aggression  = args.aggression
    if args.difficulty:
        preset = get_preset(args.difficulty)
        temperature = preset["temperature"]
        aggression  = preset["aggression"]
        print(f"难度预设 '{args.difficulty}': T={temperature:.2f}, A={aggression:+.2f}")

    # 交互式模式
    if args.interactive:
        interactive_mode(model, device)
        return

    # 确定手牌
    if args.hand:
        hand13 = [int(x) for x in args.hand.split()]
        if len(hand13) != 13:
            print(f"错误：需要 13 张牌，实际 {len(hand13)} 张")
            sys.exit(1)
    else:
        hand13 = random.sample(deck_single(), 13)
        print(f"随机发牌: {hand_to_names(hand13, zh=True)}")

    # 推理
    dfs_result = py_dfs_enum_combos(hand13, max_k=args.max_k)
    result = run_inference(
        hand13, model, temperature=temperature,
        aggression=aggression, max_k=args.max_k, device=device,
    )
    print_result(result, dfs_result, show_all=args.show_all, top_k=args.top_k)

    # 扫描
    if args.sweep_t:
        sweep_temperature(hand13, model, aggression=aggression,
                          n_repeats=args.n_repeats, device=device)
    if args.sweep_a:
        sweep_aggression(hand13, model, temperature=temperature, device=device)


if __name__ == "__main__":
    main()
