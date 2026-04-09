using System;
using System.Runtime.InteropServices;

public static class TC
{
    private const string LIB = "thirteen_cards_cpp";

    [DllImport(LIB)] public static extern int tc_card_rank(int card_id);
    [DllImport(LIB)] public static extern int tc_card_suit(int card_id);

    [DllImport(LIB)] public static extern HandResultNative tc_search_pattern(int position, int[] cards, int cnt);
    [DllImport(LIB)] public static extern int tc_dfs_enum_combos(int[] hand13, IntPtr out_result, int max_k);

    [DllImport(LIB)] public static extern IntPtr tc_player_round_create(string name);
    [DllImport(LIB)] public static extern void tc_player_round_destroy(IntPtr p);
    [DllImport(LIB)] public static extern int tc_player_round_receive_hand(IntPtr p, int[] hand13);
    [DllImport(LIB)] public static extern int tc_player_round_get_hand(IntPtr p, int[] out13);
    [DllImport(LIB)] public static extern int tc_player_round_set_position(IntPtr p, int position, int[] cards, int cnt);
    [DllImport(LIB)] public static extern int tc_player_round_settle(IntPtr p);
    [DllImport(LIB)] public static extern int tc_player_round_get_round_score(IntPtr p);
    [DllImport(LIB)] public static extern int tc_player_round_has_achievement(IntPtr p, int ach);

    [DllImport(LIB)] public static extern IntPtr tc_hand_manager_create(int[] hand13);
    [DllImport(LIB)] public static extern void tc_hand_manager_destroy(IntPtr mgr);
    [DllImport(LIB)] public static extern int tc_hand_manager_select_card(IntPtr mgr, int idx);
    [DllImport(LIB)] public static extern int tc_hand_manager_deselect_card(IntPtr mgr, int idx);
    [DllImport(LIB)] public static extern int tc_hand_manager_add_to_pile(IntPtr mgr, int pos, int idx);
    [DllImport(LIB)] public static extern int tc_hand_manager_remove_from_pile(IntPtr mgr, int pos, int idx);
    [DllImport(LIB)] public static extern int tc_hand_manager_undo(IntPtr mgr);
    [DllImport(LIB)] public static extern int tc_hand_manager_pile_full(IntPtr mgr, int position);
    [DllImport(LIB)] public static extern int tc_hand_manager_submit(IntPtr mgr, IntPtr pat);

    [DllImport(LIB)] public static extern int tc_round_deal_players(IntPtr[] players, int cnt);
    [DllImport(LIB)] public static extern int tc_round_close_players(IntPtr[] players, int cnt);
}

[StructLayout(LayoutKind.Sequential)]
public struct HandResultNative
{
    public int position;
    public IntPtr hand_name;
    public int rank_order;
    public int score;
}
