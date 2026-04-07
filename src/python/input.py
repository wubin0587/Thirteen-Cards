"""
input.py
--------
C++ 共享库的 ctypes 绑定层。

职责：
  - 加载 thirteen_cards_cpp.so / .dll
  - 声明所有 C 结构体（与 pattern.h 一一对应）
  - 封装 dfs_enum_combos、search_pattern 等 C 接口
  - 返回纯 Python 原生数据结构（list / dict / dataclass）
  - 不做任何特征工程，不涉及 numpy / torch

公开接口：
  load_lib(path)                     → 加载共享库
  py_search_pattern(pos, cards)      → HandResultPy
  py_dfs_enum_combos(hand13, max_k)  → DFSCandResultPy
  card_rank(card_id)                 → int  (0=2 … 12=A)
  card_suit(card_id)                 → int  (0=D 1=C 2=H 3=S)
  card_name(card_id)                 → str  e.g. "AH"
"""

import ctypes
import os
import sys
import platform
from dataclasses import dataclass, field
from typing import List, Optional

# ============================================================
# 1.  共享库路径解析
# ============================================================

def _default_lib_path() -> str:
    """根据平台推断默认的共享库路径。"""
    base = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "build")
    )
    system = platform.system()
    if system == "Windows":
        name = "thirteen_cards_cpp.dll"
    elif system == "Darwin":
        name = "libthirteen_cards_cpp.dylib"
    else:
        name = "libthirteen_cards_cpp.so"
    return os.path.join(base, name)


_lib: Optional[ctypes.CDLL] = None  # 全局单例
_use_tc_card_utils = False


def load_lib(path: Optional[str] = None) -> ctypes.CDLL:
    """
    加载共享库，返回 ctypes.CDLL 实例。

    重复调用时若路径相同直接返回缓存；路径不同则重新加载。

    Parameters
    ----------
    path : str, optional
        共享库文件路径。为 None 时使用平台默认路径。
    """
    global _lib
    resolved = path or _default_lib_path()
    if _lib is not None:
        return _lib
    if not os.path.isfile(resolved):
        raise FileNotFoundError(
            f"[input.py] 找不到共享库: {resolved}\n"
            "请先用 CMake 编译 C++ 模块（cmake --build build）。"
        )
    _lib = ctypes.CDLL(resolved)
    _declare_signatures(_lib)
    return _lib


def get_lib() -> ctypes.CDLL:
    """获取已加载的库；若尚未加载则使用默认路径自动加载。"""
    if _lib is None:
        load_lib()
    return _lib


# ============================================================
# 2.  C 结构体定义（与 pattern.h 完全对应）
# ============================================================

class _HandResult(ctypes.Structure):
    """对应 C 的 HandResult。"""
    _fields_ = [
        ("position",   ctypes.c_int),
        ("hand_name",  ctypes.c_char_p),
        ("rank_order", ctypes.c_int),
        ("score",      ctypes.c_int),
    ]


class _HandUnit(ctypes.Structure):
    """对应 C 的 HandUnit。"""
    _fields_ = [
        ("card_count", ctypes.c_int),
        ("cards",      ctypes.c_int * 5),
        ("result",     _HandResult),
    ]


class _HandCombo(ctypes.Structure):
    """对应 C 的 HandCombo。"""
    _fields_ = [
        ("unit_count",   ctypes.c_int),
        ("units",        _HandUnit * 3),
        ("typed_score",  ctypes.c_int),
        ("loose_count",  ctypes.c_int),
        ("loose_cards",  ctypes.c_int * 13),
    ]


class _DFSCandResult(ctypes.Structure):
    """对应 C 的 DFSCandResult。"""
    _fields_ = [
        ("is_special",    ctypes.c_int),
        ("special_score", ctypes.c_int),
        ("special_name",  ctypes.c_char_p),
        ("combo_count",   ctypes.c_int),
        ("combos",        _HandCombo * 128),
    ]


# ============================================================
# 3.  函数签名声明
# ============================================================

def _declare_signatures(lib: ctypes.CDLL) -> None:
    """为所有导出函数设置 argtypes / restype，防止未定义行为。"""
    global _use_tc_card_utils

    # HandResult tc_search_pattern(int position, const int* cards, int cnt)
    lib.tc_search_pattern.argtypes = [
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_int),
        ctypes.c_int,
    ]
    lib.tc_search_pattern.restype = _HandResult

    # int tc_dfs_enum_combos(const int hand13[13], DFSCandResult* out, int max_k)
    lib.tc_dfs_enum_combos.argtypes = [
        ctypes.POINTER(ctypes.c_int),
        ctypes.POINTER(_DFSCandResult),
        ctypes.c_int,
    ]
    lib.tc_dfs_enum_combos.restype = ctypes.c_int

    # tc_player_round_t tc_player_round_create(const char* name)
    lib.tc_player_round_create.argtypes = [ctypes.c_char_p]
    lib.tc_player_round_create.restype = ctypes.c_void_p
    lib.tc_player_round_destroy.argtypes = [ctypes.c_void_p]
    lib.tc_player_round_destroy.restype = None
    lib.tc_player_round_receive_hand.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int)]
    lib.tc_player_round_receive_hand.restype = ctypes.c_int
    lib.tc_player_round_set_position.argtypes = [
        ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_int), ctypes.c_int
    ]
    lib.tc_player_round_set_position.restype = ctypes.c_int
    lib.tc_player_round_settle.argtypes = [ctypes.c_void_p]
    lib.tc_player_round_settle.restype = ctypes.c_int
    lib.tc_player_round_get_round_score.argtypes = [ctypes.c_void_p]
    lib.tc_player_round_get_round_score.restype = ctypes.c_int

    # round helpers
    lib.tc_round_close_players.argtypes = [ctypes.POINTER(ctypes.c_void_p), ctypes.c_int]
    lib.tc_round_close_players.restype = ctypes.c_int

    # card utils（老库可能未导出，做兼容）
    try:
        lib.tc_card_rank.argtypes = [ctypes.c_int]
        lib.tc_card_rank.restype = ctypes.c_int
        lib.tc_card_suit.argtypes = [ctypes.c_int]
        lib.tc_card_suit.restype = ctypes.c_int
        _use_tc_card_utils = True
    except AttributeError:
        _use_tc_card_utils = False

    # int tc_pattern_init(const int hand13[13], Pattern* out)
    # Pattern 结构体仅供外部使用，这里不封装，仅声明最小接口


# ============================================================
# 4.  Python 端数据类（纯 Python，无 ctypes 泄漏）
# ============================================================

@dataclass
class HandResultPy:
    """search_pattern 的 Python 返回值。"""
    position:   int    # 0=head 1=middle 2=tail 3=special
    hand_name:  str
    rank_order: int    # 牌型等级，越大越强
    score:      int    # 水数


@dataclass
class HandUnitPy:
    """一个有牌型的组成单元。"""
    card_count: int        # 3 或 5
    cards:      List[int]  # 实际牌号（头墩只用前3个）
    result:     HandResultPy


@dataclass
class HandComboPy:
    """一种合法的牌型组合（不指定墩位）。"""
    unit_count:  int
    units:       List[HandUnitPy]
    typed_score: int
    loose_count: int
    loose_cards: List[int]  # 散牌，按点数降序


@dataclass
class DFSCandResultPy:
    """dfs_enum_combos 的完整输出。"""
    is_special:    bool
    special_score: int
    special_name:  str
    combo_count:   int
    combos:        List[HandComboPy] = field(default_factory=list)


# ============================================================
# 5.  类型转换：ctypes → Python 数据类
# ============================================================

def _conv_hand_result(r: _HandResult) -> HandResultPy:
    name = r.hand_name.decode("utf-8") if r.hand_name else "Unknown"
    return HandResultPy(
        position=r.position,
        hand_name=name,
        rank_order=r.rank_order,
        score=r.score,
    )


def _conv_hand_unit(u: _HandUnit) -> HandUnitPy:
    cnt = u.card_count
    cards = [u.cards[i] for i in range(cnt)]
    return HandUnitPy(
        card_count=cnt,
        cards=cards,
        result=_conv_hand_result(u.result),
    )


def _conv_hand_combo(c: _HandCombo) -> HandComboPy:
    units = [_conv_hand_unit(c.units[i]) for i in range(c.unit_count)]
    loose = [c.loose_cards[i] for i in range(c.loose_count)]
    return HandComboPy(
        unit_count=c.unit_count,
        units=units,
        typed_score=c.typed_score,
        loose_count=c.loose_count,
        loose_cards=loose,
    )


def _conv_dfs_result(r: _DFSCandResult) -> DFSCandResultPy:
    sp_name = r.special_name.decode("utf-8") if r.special_name else ""
    combos = [_conv_hand_combo(r.combos[i]) for i in range(r.combo_count)]
    return DFSCandResultPy(
        is_special=bool(r.is_special),
        special_score=r.special_score,
        special_name=sp_name,
        combo_count=r.combo_count,
        combos=combos,
    )


# ============================================================
# 6.  公开 Python 接口
# ============================================================

def py_search_pattern(position: int, cards: List[int]) -> HandResultPy:
    """
    调用 C++ search_pattern，返回牌型结果。

    Parameters
    ----------
    position : int
        0=头墩(3张)  1=中墩(5张)  2=尾墩(5张)  3=特殊(13张)
    cards : List[int]
        牌号列表，长度需与 position 匹配。
    """
    lib = get_lib()
    arr = (ctypes.c_int * len(cards))(*cards)
    raw = lib.tc_search_pattern(position, arr, len(cards))
    return _conv_hand_result(raw)


def py_dfs_enum_combos(
    hand13: List[int],
    max_k: int = 32,
) -> DFSCandResultPy:
    """
    调用 C++ dfs_enum_combos，枚举手牌的所有合法理牌方案。

    Parameters
    ----------
    hand13 : List[int]
        恰好 13 张牌的牌号列表。
    max_k : int
        最多保留的候选组合数，建议 32~64。

    Returns
    -------
    DFSCandResultPy
        若 is_special=True，则 combos 为空，直接使用 special_score。
        否则 combos 按 typed_score 降序排列，最多 max_k 个。
    """
    if len(hand13) != 13:
        raise ValueError(f"hand13 必须恰好 13 张，实际收到 {len(hand13)} 张")
    lib = get_lib()
    arr = (ctypes.c_int * 13)(*hand13)
    out = _DFSCandResult()
    rc = lib.tc_dfs_enum_combos(arr, ctypes.byref(out), max_k)
    if rc != 0:
        raise RuntimeError(f"dfs_enum_combos 返回错误码 {rc}")
    return _conv_dfs_result(out)


def py_player_round_score(
    hand13: List[int],
    head_cards: List[int],
    middle_cards: List[int],
    tail_cards: List[int],
) -> int:
    """使用 C++ PlayerRound 接口计算一手牌的结算分。"""
    if len(hand13) != 13:
        raise ValueError(f"hand13 必须恰好 13 张，实际收到 {len(hand13)} 张")
    if len(head_cards) != 3 or len(middle_cards) != 5 or len(tail_cards) != 5:
        raise ValueError("三墩牌数必须为 3/5/5")

    lib = get_lib()
    player = lib.tc_player_round_create(b"py_eval")
    if not player:
        raise RuntimeError("tc_player_round_create 失败")

    try:
        hand_arr = (ctypes.c_int * 13)(*hand13)
        rc = lib.tc_player_round_receive_hand(player, hand_arr)
        if rc != 0:
            raise RuntimeError(f"tc_player_round_receive_hand 返回错误码 {rc}")

        for pos, cards in ((0, head_cards), (1, middle_cards), (2, tail_cards)):
            arr = (ctypes.c_int * len(cards))(*cards)
            rc = lib.tc_player_round_set_position(player, pos, arr, len(cards))
            if rc != 0:
                raise RuntimeError(f"tc_player_round_set_position(pos={pos}) 返回错误码 {rc}")

        rc = lib.tc_player_round_settle(player)
        if rc < 0:
            raise RuntimeError(f"tc_player_round_settle 返回错误码 {rc}")
        return rc
    finally:
        lib.tc_player_round_destroy(player)


# ============================================================
# 7.  牌号工具函数（与 cards.h 保持一致，纯 Python 实现）
# ============================================================

_RANK_NAMES = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
_SUIT_NAMES = ["D", "C", "H", "S"]  # Diamond Club Heart Spade
_SUIT_CHARS_ZH = ["♦", "♣", "♥", "♠"]


def card_rank(card_id: int) -> int:
    """返回牌的点数索引 0=2 … 12=A（多副牌自动取模）。"""
    lib = _lib
    if lib is None:
        try:
            lib = get_lib()
        except Exception:
            lib = None
    if lib is not None and _use_tc_card_utils:
        return int(lib.tc_card_rank(card_id))
    return card_id % 13


def card_suit(card_id: int) -> int:
    """返回牌的花色索引 0=D 1=C 2=H 3=S（多副牌自动处理）。"""
    lib = _lib
    if lib is None:
        try:
            lib = get_lib()
        except Exception:
            lib = None
    if lib is not None and _use_tc_card_utils:
        return int(lib.tc_card_suit(card_id))
    return (card_id % 52) // 13


def card_name(card_id: int, zh: bool = False) -> str:
    """
    返回牌的可读名称，如 "AH"（英文）或 "♥A"（中文符号）。

    多副牌的第二副从 52 开始，名称与第一副相同。
    """
    r = card_rank(card_id)
    s = card_suit(card_id)
    if zh:
        return f"{_SUIT_CHARS_ZH[s]}{_RANK_NAMES[r]}"
    return f"{_RANK_NAMES[r]}{_SUIT_NAMES[s]}"


def hand_to_names(hand: List[int], zh: bool = False) -> List[str]:
    """将牌号列表转换为可读名称列表。"""
    return [card_name(c, zh) for c in hand]


def deck_single() -> List[int]:
    """返回单副牌（0~51）。"""
    return list(range(52))


def deck_double() -> List[int]:
    """返回双副牌（0~103）。"""
    return list(range(104))
