// Scripts/Game/DFSHelper.cs
// 封装 C++ tc_dfs_enum_combos 调用，将非托管内存中的 DFSCandResult
// 解析为 C# 托管类型，供 BotRunner 和 SentisRunner 使用。

using System;
using System.Runtime.InteropServices;
using UnityEngine;

// ── 托管侧镜像结构体 ─────────────────────────────────────────────────────────

public struct HandResultManaged
{
    public int    Position;
    public string HandName;
    public int    RankOrder;
    public int    Score;
}

public struct HandUnitManaged
{
    public int   CardCount;
    public int[] Cards;       // 长度等于 CardCount
    public HandResultManaged Result;
}

public struct HandComboManaged
{
    public int              UnitCount;
    public HandUnitManaged[] Units;      // 最多 3 个
    public int              TypedScore;
    public int              LooseCount;
    public int[]            LooseCards;
}

public class DFSResult
{
    public bool              IsSpecial;
    public int               SpecialScore;
    public string            SpecialName;
    public int               ComboCount;
    public HandComboManaged[] Combos;

    // ── 墩位分配辅助 ─────────────────────────────────────────────────────
    /// <summary>
    /// 将 combo 按规则分配三墩（3/5/5）。
    /// 返回 false 表示该方案倒水（非法）。
    /// </summary>
    public bool AssignPositions(
        int comboIdx,
        out int[] head, out int[] middle, out int[] tail)
    {
        head = middle = tail = null;
        if (comboIdx < 0 || comboIdx >= ComboCount) return false;

        var combo = Combos[comboIdx];

        // 按 card_count 分组
        var units3 = new System.Collections.Generic.List<HandUnitManaged>();
        var units5 = new System.Collections.Generic.List<HandUnitManaged>();
        foreach (var u in combo.Units)
        {
            if (u.CardCount == 3) units3.Add(u);
            else if (u.CardCount == 5) units5.Add(u);
        }
        // units5 按 rank_order 升序
        units5.Sort((a, b) => a.Result.RankOrder.CompareTo(b.Result.RankOrder));

        int[] headCards   = units3.Count  > 0 ? units3[0].Cards : null;
        int[] middleCards = units5.Count >= 1 ? units5[0].Cards : null;
        int[] tailCards   = units5.Count >= 2 ? units5[1].Cards : null;

        // 用散牌填充空墩（按点数降序）
        var loose = new System.Collections.Generic.List<int>(combo.LooseCards);
        loose.Sort((a, b) => TC.tc_card_rank(b).CompareTo(TC.tc_card_rank(a)));

        if (headCards == null)
        {
            headCards = loose.Count >= 3 ? loose.GetRange(0, 3).ToArray() : null;
            if (headCards != null) loose.RemoveRange(0, 3);
        }
        if (middleCards == null)
        {
            middleCards = loose.Count >= 5 ? loose.GetRange(0, 5).ToArray() : null;
            if (middleCards != null) loose.RemoveRange(0, 5);
        }
        if (tailCards == null)
        {
            tailCards = loose.Count >= 5 ? loose.GetRange(0, 5).ToArray() : null;
        }

        if (headCards == null || middleCards == null || tailCards == null) return false;
        if (headCards.Length != 3 || middleCards.Length != 5 || tailCards.Length != 5)
            return false;

        // 验证不倒水
        var hrH = TC.tc_search_pattern(0, headCards,   3);
        var hrM = TC.tc_search_pattern(1, middleCards, 5);
        var hrT = TC.tc_search_pattern(2, tailCards,   5);

        if (!(hrT.rank_order >= hrM.rank_order && hrM.rank_order >= hrH.rank_order))
            return false;

        head   = headCards;
        middle = middleCards;
        tail   = tailCards;
        return true;
    }
}

// ── 非托管布局（与 C++ DFSCandResult / HandCombo / HandUnit 完全对齐）──────

[StructLayout(LayoutKind.Sequential)]
internal struct _HandResult
{
    public int    position;
    public IntPtr hand_name;   // const char*
    public int    rank_order;
    public int    score;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct _HandUnit
{
    public int card_count;
    public fixed int cards[5];
    public _HandResult result;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct _HandCombo
{
    public int  unit_count;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 3)]
    public _HandUnit[] units;     // 注：fixed struct array 需逐字段读
    public int  typed_score;
    public int  loose_count;
    public fixed int loose_cards[13];
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct _DFSCandResult
{
    public int    is_special;
    public int    special_score;
    public IntPtr special_name;  // const char*
    public int    combo_count;
    // combos[128] — 因为 fixed struct array 在 C# 里不直接支持，
    // 我们分配非托管内存后手动 Marshal.
}

/// <summary>
/// 调用 C++ tc_dfs_enum_combos，返回托管 DFSResult。
/// </summary>
public static class DFSHelper
{
    // 单个 _HandCombo 的字节大小（需与 C++ ABI 对齐，5+1+1+5+13 int + result）
    // 保守估算：每个 _HandCombo 约 (3*(5+3 int)+4 int+13 int+3 int)*4 ≈ 160 bytes
    // 实际通过 Marshal.SizeOf 获取，但因含 fixed 数组需额外处理。
    // 这里使用非托管分配 + 手动偏移读取。
    private const int MAX_COMBOS = 128;

    public static DFSResult Enumerate(int[] hand13, int maxK = 32)
    {
        if (hand13 == null || hand13.Length != 13)
        {
            Debug.LogError("[DFSHelper] hand13 must have exactly 13 cards.");
            return null;
        }

        // 分配足够大的非托管缓冲区
        // _DFSCandResult 头部(16 bytes) + combos[128] 每个约 256 bytes（保守）
        int bufSize = 16 + MAX_COMBOS * 256;
        IntPtr buf = Marshal.AllocHGlobal(bufSize);

        try
        {
            // 清零
            for (int i = 0; i < bufSize; i++)
                Marshal.WriteByte(buf, i, 0);

            int rc = TC.tc_dfs_enum_combos(hand13, buf, maxK);
            if (rc != 0)
            {
                Debug.LogError($"[DFSHelper] tc_dfs_enum_combos returned error {rc}");
                return null;
            }

            return ParseDFSResult(buf);
        }
        finally
        {
            Marshal.FreeHGlobal(buf);
        }
    }

    private static DFSResult ParseDFSResult(IntPtr buf)
    {
        var result = new DFSResult();
        int offset = 0;

        result.IsSpecial    = Marshal.ReadInt32(buf, offset) != 0; offset += 4;
        result.SpecialScore = Marshal.ReadInt32(buf, offset);      offset += 4;
        IntPtr spNamePtr    = Marshal.ReadIntPtr(buf, offset);     offset += IntPtr.Size;
        result.SpecialName  = spNamePtr != IntPtr.Zero
            ? Marshal.PtrToStringAnsi(spNamePtr) ?? ""
            : "";
        result.ComboCount   = Marshal.ReadInt32(buf, offset);      offset += 4;

        int n = Math.Min(result.ComboCount, MAX_COMBOS);
        result.Combos = new HandComboManaged[n];

        for (int i = 0; i < n; i++)
        {
            result.Combos[i] = ParseCombo(buf, ref offset);
        }

        return result;
    }

    private static HandComboManaged ParseCombo(IntPtr buf, ref int offset)
    {
        var combo = new HandComboManaged();

        combo.UnitCount  = Marshal.ReadInt32(buf, offset); offset += 4;
        int unitCount    = Math.Min(combo.UnitCount, 3);
        combo.Units      = new HandUnitManaged[unitCount];

        for (int u = 0; u < 3; u++)   // C++ 固定 3 个 unit 槽
        {
            var unit = ParseUnit(buf, ref offset);
            if (u < unitCount) combo.Units[u] = unit;
        }

        combo.TypedScore  = Marshal.ReadInt32(buf, offset); offset += 4;
        combo.LooseCount  = Marshal.ReadInt32(buf, offset); offset += 4;

        int lc = Math.Min(combo.LooseCount, 13);
        combo.LooseCards  = new int[lc];
        for (int j = 0; j < 13; j++)
        {
            int card = Marshal.ReadInt32(buf, offset); offset += 4;
            if (j < lc) combo.LooseCards[j] = card;
        }

        return combo;
    }

    private static HandUnitManaged ParseUnit(IntPtr buf, ref int offset)
    {
        var unit = new HandUnitManaged();

        unit.CardCount = Marshal.ReadInt32(buf, offset); offset += 4;
        int cc = Math.Min(unit.CardCount, 5);
        unit.Cards = new int[cc];
        for (int j = 0; j < 5; j++)
        {
            int card = Marshal.ReadInt32(buf, offset); offset += 4;
            if (j < cc) unit.Cards[j] = card;
        }

        // HandResult
        unit.Result.Position  = Marshal.ReadInt32(buf, offset); offset += 4;
        IntPtr namePtr        = Marshal.ReadIntPtr(buf, offset); offset += IntPtr.Size;
        unit.Result.HandName  = namePtr != IntPtr.Zero
            ? Marshal.PtrToStringAnsi(namePtr) ?? ""
            : "";
        unit.Result.RankOrder = Marshal.ReadInt32(buf, offset); offset += 4;
        unit.Result.Score     = Marshal.ReadInt32(buf, offset); offset += 4;

        return unit;
    }
}
