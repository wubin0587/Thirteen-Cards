// Scripts/Native/TC.cs
// P/Invoke 薄壳，直接映射 manager.h 的所有导出函数。
// 原则：一个函数对一个 C API，不加任何逻辑。

using System;
using System.Runtime.InteropServices;

public static class TC
{
    const string LIB = "thirteen_cards_cpp";

    // ── Cards utils ───────────────────────────────────────────────────────────
    [DllImport(LIB)] public static extern int tc_card_rank(int card_id);
    [DllImport(LIB)] public static extern int tc_card_suit(int card_id);

    // ── Pattern / search ──────────────────────────────────────────────────────
    [DllImport(LIB)]
    public static extern HandResultNative tc_search_pattern(
        int position, int[] cards, int cnt);

    // ── DFS 枚举 ──────────────────────────────────────────────────────────────
    [DllImport(LIB)]
    public static extern int tc_dfs_enum_combos(
        int[] hand13, IntPtr out_result, int max_k);

    // ── Pattern 结构体操作 ────────────────────────────────────────────────────
    [DllImport(LIB)]
    public static extern int tc_pattern_init(int[] hand13, IntPtr out_pattern);

    [DllImport(LIB)]
    public static extern int tc_pattern_set_position(
        IntPtr pattern, int position, int[] cards, int count);

    [DllImport(LIB)]
    public static extern int tc_pattern_get_position(
        IntPtr pattern, int position, int[] out_buf);

    [DllImport(LIB)]
    public static extern int tc_pattern_sort(IntPtr pattern);

    // ── PlayerRound ───────────────────────────────────────────────────────────
    [DllImport(LIB)]
    public static extern IntPtr tc_player_round_create(
        [MarshalAs(UnmanagedType.LPStr)] string name);

    [DllImport(LIB)]
    public static extern void tc_player_round_destroy(IntPtr player);

    [DllImport(LIB)]
    public static extern int tc_player_round_receive_hand(IntPtr player, int[] hand13);

    [DllImport(LIB)]
    public static extern int tc_player_round_set_position(
        IntPtr player, int position, int[] cards, int cnt);

    [DllImport(LIB)]
    public static extern int tc_player_round_settle(IntPtr player);

    [DllImport(LIB)]
    public static extern int tc_player_round_get_round_score(IntPtr player);

    [DllImport(LIB)]
    public static extern int tc_player_round_get_total_score(IntPtr player);

    [DllImport(LIB)]
    public static extern IntPtr tc_player_round_get_name(IntPtr player);

    [DllImport(LIB)]
    public static extern int tc_player_round_has_achievement(IntPtr player, int achievement);

    // 建议补充的接口（取本机手牌）
    [DllImport(LIB)]
    public static extern int tc_player_round_get_hand(IntPtr player, int[] out_hand13);

    // ── HandManager（选牌/放墩/撤销状态机）───────────────────────────────────
    [DllImport(LIB)]
    public static extern IntPtr tc_hand_manager_create(int[] hand13);

    [DllImport(LIB)]
    public static extern void tc_hand_manager_destroy(IntPtr mgr);

    [DllImport(LIB)]
    public static extern int tc_hand_manager_select_card(IntPtr mgr, int idx);

    [DllImport(LIB)]
    public static extern int tc_hand_manager_deselect_card(IntPtr mgr, int idx);

    [DllImport(LIB)]
    public static extern int tc_hand_manager_add_to_pile(IntPtr mgr, int position, int idx);

    [DllImport(LIB)]
    public static extern int tc_hand_manager_remove_from_pile(IntPtr mgr, int position, int idx);

    [DllImport(LIB)]
    public static extern int tc_hand_manager_undo(IntPtr mgr);

    [DllImport(LIB)]
    public static extern int tc_hand_manager_pile_full(IntPtr mgr, int position);

    [DllImport(LIB)]
    public static extern int tc_hand_manager_submit(IntPtr mgr, IntPtr pattern);

    // ── Round ─────────────────────────────────────────────────────────────────
    [DllImport(LIB)]
    public static extern int tc_round_deal_players(IntPtr[] players, int cnt);

    [DllImport(LIB)]
    public static extern int tc_round_close_players(IntPtr[] players, int cnt);
}

// ── C++ HandResult 的 blittable 镜像 ─────────────────────────────────────────
[StructLayout(LayoutKind.Sequential)]
public struct HandResultNative
{
    public int    position;
    public IntPtr hand_name;    // const char*，用 Marshal.PtrToStringAnsi 读
    public int    rank_order;
    public int    score;

    /// <summary>将 hand_name 指针解码为托管字符串。</summary>
    public string HandName => Marshal.PtrToStringAnsi(hand_name) ?? string.Empty;
}

// ── Achievement 枚举（对应 C++ Achievement）────────────────────────────────────
public enum Achievement
{
    None    = 0,
    Shoot   = 1,   // 打枪
    Homerun = 2,   // 全垒打
}

// ── Round 错误码常量 ──────────────────────────────────────────────────────────
public static class RoundError
{
    public const int Ok      =  0;
    public const int Null    = -1;
    public const int Players = -2;
    public const int Deal    = -3;
}
