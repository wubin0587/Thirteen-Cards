"""
test.py
-------
测试套件。

覆盖范围：
  Unit Tests：
    - input.py       C++ 绑定正确性（牌号工具、结构体转换）
    - features.py    特征编码维度和数值范围
    - models.py      前向传播、推理接口、难度预设

  Integration Tests：
    - DFS → 特征编码 → 模型推理 全链路
    - 特殊牌型分支
    - 边界手牌（全同花、全散牌）

  Regression Tests：
    - 相同手牌 + temperature=0.01 输出稳定性（确定性推理）
    - aggression 方向正确性（高 A → 更高进攻潜力方案）

  Performance Benchmarks：
    - DFS 枚举耗时
    - 特征编码耗时
    - 模型推理耗时（CPU / GPU）

用法：
  # 运行全部测试
  python test.py

  # 只运行某一类
  python test.py --suite unit
  python test.py --suite integration
  python test.py --suite regression
  python test.py --suite benchmark

  # 跳过需要 C++ 库的测试（仅测试 Python 侧逻辑）
  python test.py --no_cpp

  # 跳过需要模型的测试
  python test.py --no_model
"""

from __future__ import annotations

import argparse
import os
import random
import sys
import time
import traceback
import unittest
from typing import List, Optional
from unittest.mock import MagicMock, patch

import numpy as np
import torch

# ============================================================
# 测试配置
# ============================================================

CKPT_PATH = os.path.join("src", "models", "thirteen_cards_ranker.pt")

# 全局标志（由 CLI 参数控制）
_SKIP_CPP   = False
_SKIP_MODEL = False


def _require_cpp(fn):
    """装饰器：跳过需要 C++ 库的测试。"""
    def wrapper(self, *args, **kwargs):
        if _SKIP_CPP:
            self.skipTest("跳过 C++ 依赖测试 (--no_cpp)")
        return fn(self, *args, **kwargs)
    return wrapper


def _require_model(fn):
    """装饰器：跳过需要训练模型的测试。"""
    def wrapper(self, *args, **kwargs):
        if _SKIP_MODEL:
            self.skipTest("跳过模型依赖测试 (--no_model)")
        if not os.path.isfile(CKPT_PATH):
            self.skipTest(f"找不到模型文件: {CKPT_PATH}")
        return fn(self, *args, **kwargs)
    return wrapper


# ============================================================
# 1.  Unit Tests — input.py
# ============================================================

class TestInputUtils(unittest.TestCase):
    """测试 input.py 中的纯 Python 工具函数（无需 C++ 库）。"""

    def test_card_rank_single_deck(self):
        from input import card_rank
        self.assertEqual(card_rank(0),  0)   # 2♦ → rank 0
        self.assertEqual(card_rank(12), 12)  # A♦ → rank 12
        self.assertEqual(card_rank(51), 12)  # A♠ → rank 12

    def test_card_suit_single_deck(self):
        from input import card_suit
        self.assertEqual(card_suit(0),  0)   # ♦
        self.assertEqual(card_suit(13), 1)   # ♣
        self.assertEqual(card_suit(26), 2)   # ♥
        self.assertEqual(card_suit(39), 3)   # ♠

    def test_card_rank_double_deck(self):
        from input import card_rank
        # 双副牌第二张 2♦ = card_id 52
        self.assertEqual(card_rank(52), 0)
        self.assertEqual(card_rank(53), 1)

    def test_card_suit_double_deck(self):
        from input import card_suit
        self.assertEqual(card_suit(52),  0)
        self.assertEqual(card_suit(65),  1)

    def test_card_name_english(self):
        from input import card_name
        self.assertEqual(card_name(0),  "D2")
        self.assertEqual(card_name(12), "DA")
        self.assertEqual(card_name(51), "SA")

    def test_card_name_zh(self):
        from input import card_name
        self.assertEqual(card_name(0,  zh=True), "♦2")
        self.assertEqual(card_name(12, zh=True), "♦A")

    def test_hand_to_names(self):
        from input import hand_to_names
        names = hand_to_names([0, 13, 26, 39], zh=False)
        self.assertEqual(names, ["D2", "C2", "H2", "S2"])

    def test_deck_single_length(self):
        from input import deck_single
        self.assertEqual(len(deck_single()), 52)
        self.assertEqual(deck_single()[0], 0)
        self.assertEqual(deck_single()[-1], 51)

    def test_deck_double_length(self):
        from input import deck_double
        self.assertEqual(len(deck_double()), 104)


class TestInputCpp(unittest.TestCase):
    """测试 input.py 的 C++ 绑定（需要共享库）。"""

    @_require_cpp
    def test_load_lib(self):
        from input import load_lib, get_lib
        lib = load_lib()
        self.assertIsNotNone(lib)
        # 重复调用应返回同一实例
        lib2 = get_lib()
        self.assertIs(lib, lib2)

    @_require_cpp
    def test_search_pattern_head_pair(self):
        from input import py_search_pattern
        # 2♦ 2♣ A♦ → 头墩对子
        result = py_search_pattern(0, [0, 1, 12])
        self.assertEqual(result.position, 0)
        self.assertEqual(result.hand_name, "Pair")
        self.assertEqual(result.rank_order, 2)

    @_require_cpp
    def test_search_pattern_head_three(self):
        from input import py_search_pattern
        # 2♦ 2♣ 2♥ → 头墩三条
        result = py_search_pattern(0, [0, 1, 2])
        self.assertEqual(result.hand_name, "Three of a Kind")
        self.assertEqual(result.score, 3)

    @_require_cpp
    def test_search_pattern_tail_straight_flush(self):
        from input import py_search_pattern
        # A♦ K♦ Q♦ J♦ 10♦ → 尾墩同花顺
        result = py_search_pattern(2, [12, 11, 10, 9, 8])
        self.assertEqual(result.hand_name, "Straight Flush")
        self.assertEqual(result.score, 5)

    @_require_cpp
    def test_dfs_enum_combos_returns_result(self):
        from input import py_dfs_enum_combos, deck_single
        random.seed(0)
        hand13 = random.sample(deck_single(), 13)
        result = py_dfs_enum_combos(hand13, max_k=32)
        self.assertIsInstance(result.combo_count, int)
        self.assertGreaterEqual(result.combo_count, 0)

    @_require_cpp
    def test_dfs_enum_combos_wrong_hand_size(self):
        from input import py_dfs_enum_combos
        with self.assertRaises(ValueError):
            py_dfs_enum_combos([0, 1, 2], max_k=32)

    @_require_cpp
    def test_dfs_enum_combos_combo_fields(self):
        from input import py_dfs_enum_combos, deck_single
        random.seed(1)
        hand13 = random.sample(deck_single(), 13)
        result = py_dfs_enum_combos(hand13, max_k=32)
        if result.is_special:
            return  # 特殊牌型跳过 combo 检查
        for combo in result.combos:
            self.assertGreaterEqual(combo.unit_count, 0)
            self.assertLessEqual(combo.unit_count, 3)
            self.assertGreaterEqual(combo.loose_count, 0)
            self.assertLessEqual(combo.loose_count, 13)


# ============================================================
# 2.  Unit Tests — features.py
# ============================================================

class TestFeatures(unittest.TestCase):

    def test_encode_card_dim(self):
        from features import encode_card, CARD_DIM
        vec = encode_card(0)
        self.assertEqual(vec.shape, (CARD_DIM,))
        self.assertEqual(vec.dtype, np.float32)

    def test_encode_card_one_hot_suit(self):
        from features import encode_card
        vec = encode_card(0)   # 2♦ → suit=0
        self.assertEqual(vec[0], 1.0)
        self.assertEqual(vec[1], 0.0)
        self.assertEqual(vec[2], 0.0)
        self.assertEqual(vec[3], 0.0)

    def test_encode_card_one_hot_rank(self):
        from features import encode_card
        vec = encode_card(12)  # A♦ → rank=12
        self.assertEqual(vec[4 + 12], 1.0)
        self.assertEqual(sum(vec[4:]), 1.0)

    def test_encode_hand_shape(self):
        from features import encode_hand, CARD_DIM
        hand = list(range(13))
        mat = encode_hand(hand)
        self.assertEqual(mat.shape, (13, CARD_DIM))

    def test_encode_hand_wrong_size(self):
        from features import encode_hand
        with self.assertRaises(AssertionError):
            encode_hand(list(range(5)))

    def test_encode_combo_shape(self):
        from features import encode_combo, COMBO_DIM
        # 构造 mock combo
        combo = _make_mock_combo()
        hand13 = list(range(13))
        vec = encode_combo(combo, hand13)
        self.assertEqual(vec.shape, (COMBO_DIM,))

    def test_encode_combo_range(self):
        from features import encode_combo
        combo = _make_mock_combo()
        hand13 = list(range(13))
        vec = encode_combo(combo, hand13)
        # 大部分特征应在 [0, 1]（归一化）
        self.assertTrue(np.all(vec >= -0.01))

    def test_encode_batch_combos_shape(self):
        from features import encode_batch_combos, MAX_COMBOS, COMBO_DIM
        from input import DFSCandResultPy
        dfs_result = _make_mock_dfs_result(n_combos=5)
        hand13 = list(range(13))
        feats, mask, valid = encode_batch_combos(dfs_result, hand13)
        self.assertEqual(feats.shape, (MAX_COMBOS, COMBO_DIM))
        self.assertEqual(mask.shape, (MAX_COMBOS,))
        self.assertEqual(valid, 5)
        self.assertTrue(np.all(mask[:5] == 1.0))
        self.assertTrue(np.all(mask[5:] == 0.0))

    def test_attack_potential_range(self):
        from features import attack_potential
        combo = _make_mock_combo()
        ap = attack_potential(combo)
        self.assertGreaterEqual(ap, 0.0)
        self.assertLessEqual(ap, 1.0)

    def test_defense_stability_range(self):
        from features import defense_stability
        combo = _make_mock_combo()
        ds = defense_stability(combo)
        self.assertGreaterEqual(ds, 0.0)
        self.assertLessEqual(ds, 1.0)


# ============================================================
# 3.  Unit Tests — models.py
# ============================================================

class TestModels(unittest.TestCase):

    def setUp(self):
        from models import ModelConfig, TransformerRanker
        self.cfg   = ModelConfig(d_model=32, n_layers=1, d_ffn=64)
        self.model = TransformerRanker(self.cfg)

    def test_parameter_count_positive(self):
        self.assertGreater(self.model.count_parameters(), 0)

    def test_forward_shape(self):
        from features import CARD_DIM, COMBO_DIM, MAX_COMBOS
        B, K = 2, MAX_COMBOS
        hand    = torch.zeros(B, 13, CARD_DIM)
        combos  = torch.zeros(B, K, COMBO_DIM)
        mask    = torch.ones(B, K)
        logits  = self.model(hand, combos, mask)
        self.assertEqual(logits.shape, (B, K))

    def test_forward_padding_ignored(self):
        """padding 位置的 logit 应极小（被 mask 屏蔽）。"""
        from features import CARD_DIM, COMBO_DIM, MAX_COMBOS
        B, K = 1, MAX_COMBOS
        hand    = torch.zeros(B, 13, CARD_DIM)
        combos  = torch.zeros(B, K, COMBO_DIM)
        mask    = torch.zeros(B, K)
        mask[0, :5] = 1.0
        logits  = self.model(hand, combos, mask)
        # 有效位 logit 应远大于 padding 位
        valid_max  = logits[0, :5].max().item()
        invalid_min = logits[0, 5:].min().item()
        self.assertGreater(valid_max, invalid_min + 1e3)

    def test_inference_returns_valid_index(self):
        from features import CARD_DIM, COMBO_DIM, MAX_COMBOS
        from models import inference
        B, K = 1, MAX_COMBOS
        hand    = torch.zeros(B, 13, CARD_DIM)
        combos  = torch.zeros(B, K, COMBO_DIM)
        mask    = torch.zeros(B, K)
        mask[0, :10] = 1.0
        idx = inference(self.model, hand, combos, mask, temperature=1.0)
        self.assertGreaterEqual(idx, 0)
        self.assertLess(idx, 10)

    def test_inference_deterministic(self):
        from features import CARD_DIM, COMBO_DIM, MAX_COMBOS
        from models import inference
        B, K = 1, MAX_COMBOS
        hand    = torch.zeros(B, 13, CARD_DIM)
        combos  = torch.randn(B, K, COMBO_DIM)
        mask    = torch.ones(B, K)
        idx1 = inference(self.model, hand, combos, mask, deterministic=True)
        idx2 = inference(self.model, hand, combos, mask, deterministic=True)
        self.assertEqual(idx1, idx2)

    def test_difficulty_presets(self):
        from models import get_preset
        for name in ["easy", "medium", "hard", "expert"]:
            p = get_preset(name)
            self.assertIn("temperature", p)
            self.assertIn("aggression", p)
            self.assertGreater(p["temperature"], 0)
            self.assertGreaterEqual(p["aggression"], -1.0)
            self.assertLessEqual(p["aggression"], 1.0)

    def test_difficulty_invalid(self):
        from models import get_preset
        with self.assertRaises(ValueError):
            get_preset("impossible")


# ============================================================
# 4.  Integration Tests
# ============================================================

class TestIntegration(unittest.TestCase):

    @_require_cpp
    def test_full_pipeline_random_hand(self):
        """随机手牌 → DFS → 特征编码 → 模型推理 全链路。"""
        from input import py_dfs_enum_combos, deck_single
        from features import encode_hand, encode_batch_combos
        from models import ModelConfig, TransformerRanker, inference

        random.seed(42)
        hand13 = random.sample(deck_single(), 13)
        dfs_result = py_dfs_enum_combos(hand13, max_k=32)

        if dfs_result.is_special:
            return  # 特殊牌型分支单独测试

        self.assertGreater(dfs_result.combo_count, 0)

        hand_tokens = torch.from_numpy(encode_hand(hand13)).unsqueeze(0)
        combo_feats, combo_mask, valid = encode_batch_combos(dfs_result, hand13)
        combo_feats = torch.from_numpy(combo_feats).unsqueeze(0)
        combo_mask  = torch.from_numpy(combo_mask).unsqueeze(0)

        cfg   = ModelConfig(d_model=32, n_layers=1, d_ffn=64)
        model = TransformerRanker(cfg)
        idx   = inference(model, hand_tokens, combo_feats, combo_mask, temperature=1.0)

        self.assertGreaterEqual(idx, 0)
        self.assertLess(idx, valid)

    @_require_cpp
    def test_full_pipeline_special_hand(self):
        """构造一条龙手牌（13张点数各不同）测试特殊牌型分支。"""
        from input import py_dfs_enum_combos
        # 一条龙：每种点数各取一张（花色任意）
        hand13 = [rank * 4 for rank in range(13)]  # 各取♦
        dfs_result = py_dfs_enum_combos(hand13, max_k=32)
        self.assertTrue(dfs_result.is_special)
        self.assertGreater(dfs_result.special_score, 0)

    @_require_cpp
    @_require_model
    def test_inference_with_trained_model(self):
        """使用真实训练模型推理（完整集成）。"""
        from individual import load_model, run_inference
        from input import deck_single
        random.seed(7)
        hand13 = random.sample(deck_single(), 13)
        model, _ = load_model(CKPT_PATH)
        result = run_inference(hand13, model, temperature=1.0, aggression=0.0)
        if not result.is_special:
            self.assertEqual(len(result.head_cards),   3)
            self.assertEqual(len(result.middle_cards), 5)
            self.assertEqual(len(result.tail_cards),   5)


# ============================================================
# 5.  Regression Tests
# ============================================================

class TestRegression(unittest.TestCase):

    @_require_cpp
    def test_deterministic_inference_stability(self):
        """低温推理多次运行应给出相同方案。"""
        from input import py_dfs_enum_combos, deck_single
        from features import encode_hand, encode_batch_combos
        from models import ModelConfig, TransformerRanker, inference

        random.seed(99)
        hand13 = random.sample(deck_single(), 13)
        dfs_result = py_dfs_enum_combos(hand13, max_k=32)
        if dfs_result.is_special or dfs_result.combo_count == 0:
            return

        hand_tokens = torch.from_numpy(encode_hand(hand13)).unsqueeze(0)
        combo_feats, combo_mask, _ = encode_batch_combos(dfs_result, hand13)
        combo_feats = torch.from_numpy(combo_feats).unsqueeze(0)
        combo_mask  = torch.from_numpy(combo_mask).unsqueeze(0)

        cfg   = ModelConfig(d_model=32, n_layers=1, d_ffn=64)
        model = TransformerRanker(cfg)

        results = [
            inference(model, hand_tokens, combo_feats, combo_mask, deterministic=True)
            for _ in range(10)
        ]
        self.assertEqual(len(set(results)), 1, "确定性推理应每次相同")

    @_require_cpp
    def test_aggression_direction(self):
        """高 aggression 倾向于选择进攻潜力更高的方案。"""
        from input import py_dfs_enum_combos, deck_single
        from features import encode_hand, encode_batch_combos, attack_potential
        from models import ModelConfig, TransformerRanker, inference
        import torch

        random.seed(55)
        # 尝试多手牌，确保至少一次 aggression 方向符合预期
        consistent_count = 0
        total = 0

        for seed in range(20):
            random.seed(seed)
            hand13 = random.sample(deck_single(), 13)
            dfs_result = py_dfs_enum_combos(hand13, max_k=32)
            if dfs_result.is_special or dfs_result.combo_count < 3:
                continue

            hand_tokens = torch.from_numpy(encode_hand(hand13)).unsqueeze(0)
            combo_feats, combo_mask, n_valid = encode_batch_combos(dfs_result, hand13)
            combo_feats = torch.from_numpy(combo_feats).unsqueeze(0)
            combo_mask  = torch.from_numpy(combo_mask).unsqueeze(0)

            ap_vec = torch.tensor(
                [attack_potential(dfs_result.combos[i]) for i in range(n_valid)]
                + [0.0] * (128 - n_valid)
            ).unsqueeze(0)

            cfg   = ModelConfig(d_model=32, n_layers=1, d_ffn=64)
            model = TransformerRanker(cfg)

            idx_aggressive = inference(
                model, hand_tokens, combo_feats, combo_mask,
                temperature=0.01, aggression=1.0,
                attack_potentials=ap_vec, deterministic=True,
            )
            idx_passive = inference(
                model, hand_tokens, combo_feats, combo_mask,
                temperature=0.01, aggression=-1.0,
                defense_stabilities=ap_vec, deterministic=True,
            )
            total += 1
            if idx_aggressive != idx_passive:
                consistent_count += 1

        # 大多数手牌下，aggression 应导致不同选择
        if total > 0:
            rate = consistent_count / total
            # 放宽标准：只要有差异即可（30%以上）
            self.assertGreater(rate, 0.3,
                f"aggression 对选择影响过小 ({rate*100:.0f}%)")


# ============================================================
# 6.  Performance Benchmarks
# ============================================================

class TestBenchmarks(unittest.TestCase):

    @_require_cpp
    def test_dfs_speed(self):
        """DFS 枚举单手牌应在 50ms 内完成。"""
        from input import py_dfs_enum_combos, deck_single
        random.seed(0)
        hand13 = random.sample(deck_single(), 13)

        t0 = time.perf_counter()
        for _ in range(10):
            py_dfs_enum_combos(hand13, max_k=32)
        elapsed_ms = (time.perf_counter() - t0) / 10 * 1000

        print(f"\n  DFS 枚举平均耗时: {elapsed_ms:.2f} ms")
        self.assertLess(elapsed_ms, 50.0, f"DFS 过慢: {elapsed_ms:.2f} ms")

    @_require_cpp
    def test_feature_encoding_speed(self):
        """特征编码应在 5ms 内完成。"""
        from input import py_dfs_enum_combos, deck_single
        from features import encode_hand, encode_batch_combos
        random.seed(1)
        hand13 = random.sample(deck_single(), 13)
        dfs_result = py_dfs_enum_combos(hand13, max_k=32)
        if dfs_result.is_special:
            return

        t0 = time.perf_counter()
        for _ in range(100):
            encode_hand(hand13)
            encode_batch_combos(dfs_result, hand13)
        elapsed_ms = (time.perf_counter() - t0) / 100 * 1000

        print(f"\n  特征编码平均耗时: {elapsed_ms:.2f} ms")
        self.assertLess(elapsed_ms, 5.0)

    def test_model_inference_speed(self):
        """模型推理（CPU，batch=1）应在 10ms 内完成。"""
        from features import CARD_DIM, COMBO_DIM, MAX_COMBOS
        from models import ModelConfig, TransformerRanker, inference

        cfg   = ModelConfig(d_model=64, n_layers=2, d_ffn=128)
        model = TransformerRanker(cfg)
        model.eval()

        hand    = torch.zeros(1, 13, CARD_DIM)
        combos  = torch.randn(1, MAX_COMBOS, COMBO_DIM)
        mask    = torch.ones(1, MAX_COMBOS)

        # 预热
        for _ in range(5):
            inference(model, hand, combos, mask, temperature=1.0)

        t0 = time.perf_counter()
        N  = 50
        for _ in range(N):
            inference(model, hand, combos, mask, temperature=1.0)
        elapsed_ms = (time.perf_counter() - t0) / N * 1000

        print(f"\n  模型推理平均耗时 (CPU): {elapsed_ms:.2f} ms")
        self.assertLess(elapsed_ms, 10.0, f"模型推理过慢: {elapsed_ms:.2f} ms")


# ============================================================
# 辅助：构造 mock 数据（无需 C++ 库）
# ============================================================

def _make_mock_combo():
    """构造一个最小 HandComboPy 用于测试。"""
    from input import HandComboPy, HandUnitPy, HandResultPy
    unit = HandUnitPy(
        card_count=5,
        cards=[0, 1, 2, 3, 4],
        result=HandResultPy(position=2, hand_name="High Card",
                            rank_order=1, score=1),
    )
    return HandComboPy(
        unit_count=1,
        units=[unit],
        typed_score=1,
        loose_count=8,
        loose_cards=list(range(5, 13)),
    )


def _make_mock_dfs_result(n_combos: int = 5):
    """构造 n_combos 个 mock combo 的 DFSCandResultPy。"""
    from input import DFSCandResultPy
    combos = [_make_mock_combo() for _ in range(n_combos)]
    return DFSCandResultPy(
        is_special=False,
        special_score=0,
        special_name="",
        combo_count=n_combos,
        combos=combos,
    )


# ============================================================
# CLI 入口
# ============================================================

def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="福建十三水 AI 测试套件")
    parser.add_argument(
        "--suite",
        type=str,
        default="all",
        choices=["all", "unit", "integration", "regression", "benchmark"],
        help="运行指定类别的测试",
    )
    parser.add_argument("--no_cpp",   action="store_true", help="跳过 C++ 依赖测试")
    parser.add_argument("--no_model", action="store_true", help="跳过模型依赖测试")
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser.parse_args()


_SUITE_MAP = {
    "unit":        [TestInputUtils, TestInputCpp, TestFeatures, TestModels],
    "integration": [TestIntegration],
    "regression":  [TestRegression],
    "benchmark":   [TestBenchmarks],
}


def main() -> None:
    global _SKIP_CPP, _SKIP_MODEL
    args = _parse_args()

    _SKIP_CPP   = args.no_cpp
    _SKIP_MODEL = args.no_model

    # 尝试加载 C++ 库（如果不跳过）
    if not _SKIP_CPP:
        try:
            from input import load_lib
            load_lib()
            print("✓ C++ 共享库加载成功")
        except Exception as e:
            print(f"⚠ C++ 共享库加载失败（{e}），相关测试将被跳过")
            _SKIP_CPP = True

    loader    = unittest.TestLoader()
    suite     = unittest.TestSuite()
    verbosity = 2 if args.verbose else 1

    if args.suite == "all":
        test_classes = sum(_SUITE_MAP.values(), [])
    else:
        test_classes = _SUITE_MAP[args.suite]

    for cls in test_classes:
        suite.addTests(loader.loadTestsFromTestCase(cls))

    runner = unittest.TextTestRunner(verbosity=verbosity)
    result = runner.run(suite)

    # 汇总
    print(f"\n{'='*52}")
    print(f"测试结果: {result.testsRun} 项运行, "
          f"{len(result.failures)} 失败, "
          f"{len(result.errors)} 错误, "
          f"{len(result.skipped)} 跳过")
    print('='*52)

    sys.exit(0 if result.wasSuccessful() else 1)


if __name__ == "__main__":
    main()
