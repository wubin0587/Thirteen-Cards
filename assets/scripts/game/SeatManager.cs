// Scripts/Game/SeatManager.cs
// 按人数激活/隐藏槽位，横屏下计算坐标。
// 本机(seat 0)固定底部中央，对手(1~n-1)在上方区域均匀分布。

using UnityEngine;

public class SeatManager : MonoBehaviour
{
    // ── 序列化字段 ────────────────────────────────────────────────────────────
    [Header("Slot References (Inspector 预配置 12 个)")]
    [SerializeField] private PlayerSlotView[] _slots;   // 12 个，Index 0 = 本机

    [Header("Layout Anchors (0~1 百分比)")]
    [SerializeField] private RectTransform _opponentArea;   // 上方对手区容器
    [SerializeField] private RectTransform _mySlotAnchor;   // 本机槽位锚点

    [Header("Layout Settings")]
    [SerializeField] private float slotSpacingH = 0.12f;    // 水平间距比例
    [SerializeField] private float slotRowOffsetV = 0.12f;  // 双行时行间距

    // ─────────────────────────────────────────────────────────────────────────
    /// <summary>根据 RoomConfig 初始化所有槽位。</summary>
    public void Setup(RoomConfig cfg)
    {
        int n = cfg.PlayerCount;

        // 激活/隐藏
        for (int i = 0; i < 12; i++)
        {
            if (_slots[i] != null)
                _slots[i].gameObject.SetActive(i < n);
        }

        // 初始化每个槽的数据
        for (int i = 0; i < n; i++)
        {
            if (_slots[i] != null)
                _slots[i].Init(cfg.Seats[i], isMySlot: i == 0);
        }

        // 本机槽固定底部
        if (_slots[0] != null && _mySlotAnchor != null)
            _slots[0].GetComponent<RectTransform>().SetParent(_mySlotAnchor, false);

        // 对手槽重新排布
        ArrangeOpponentSlots(n);
    }

    // ── 对手槽位布局 ─────────────────────────────────────────────────────────
    private void ArrangeOpponentSlots(int n)
    {
        if (_opponentArea == null) return;

        int opCount = n - 1;   // 对手数量

        // 每个对手的 RectTransform 父节点改为对手区
        for (int i = 1; i < n; i++)
        {
            if (_slots[i] == null) continue;
            var rt = _slots[i].GetComponent<RectTransform>();
            rt.SetParent(_opponentArea, false);
        }

        // 根据数量选择布局策略
        if (opCount <= 5)
            LayoutSingleRow(opCount);
        else if (opCount <= 9)
            LayoutTwoRows(opCount);
        else
            LayoutTwoRowsWithSide(opCount);
    }

    /// <summary>单行均匀分布（对手 ≤ 5）。</summary>
    private void LayoutSingleRow(int count)
    {
        float step  = count > 1 ? 1f / (count + 1) : 0.5f;
        float yAnchor = 0.75f;  // 距离顶部 1/4 处

        for (int i = 0; i < count; i++)
        {
            var rt = _slots[i + 1].GetComponent<RectTransform>();
            float x = step * (i + 1);
            rt.anchorMin = rt.anchorMax = new Vector2(x, yAnchor);
            rt.anchoredPosition = Vector2.zero;
        }
    }

    /// <summary>双行分布（对手 6~9）。</summary>
    private void LayoutTwoRows(int count)
    {
        int row1Count = Mathf.CeilToInt(count / 2f);
        int row2Count = count - row1Count;

        LayoutRow(_slots, 1, row1Count, 0.85f);
        LayoutRow(_slots, 1 + row1Count, row2Count, 0.65f);
    }

    /// <summary>双行 + 左右侧列（对手 10~11）。</summary>
    private void LayoutTwoRowsWithSide(int count)
    {
        // 中间两行各 4 个，左右边各 1 个
        int midCount = count - 2;
        int row1Count = Mathf.CeilToInt(midCount / 2f);
        int row2Count = midCount - row1Count;

        LayoutRow(_slots, 1, row1Count, 0.85f);
        LayoutRow(_slots, 1 + row1Count, row2Count, 0.65f);

        // 左边
        if (count >= 10 && _slots[1 + midCount] != null)
        {
            var rt = _slots[1 + midCount].GetComponent<RectTransform>();
            rt.anchorMin = rt.anchorMax = new Vector2(0.05f, 0.75f);
            rt.anchoredPosition = Vector2.zero;
        }
        // 右边
        if (count >= 11 && _slots[1 + midCount + 1] != null)
        {
            var rt = _slots[1 + midCount + 1].GetComponent<RectTransform>();
            rt.anchorMin = rt.anchorMax = new Vector2(0.95f, 0.75f);
            rt.anchoredPosition = Vector2.zero;
        }
    }

    private void LayoutRow(PlayerSlotView[] slots, int startIdx, int count, float yAnchor)
    {
        float step = count > 1 ? 1f / (count + 1) : 0.5f;
        for (int i = 0; i < count; i++)
        {
            if (startIdx + i >= slots.Length || slots[startIdx + i] == null) continue;
            var rt = slots[startIdx + i].GetComponent<RectTransform>();
            float x = step * (i + 1);
            rt.anchorMin = rt.anchorMax = new Vector2(x, yAnchor);
            rt.anchoredPosition = Vector2.zero;
        }
    }

    // ── 运行时更新（思考动画、水数等）───────────────────────────────────────
    public void ShowThinking(int seat, bool show)
    {
        if (seat > 0 && seat < _slots.Length && _slots[seat] != null)
            _slots[seat].SetThinking(show);
    }

    public void UpdateScore(int seat, int roundScore, int totalScore)
    {
        if (seat < _slots.Length && _slots[seat] != null)
            _slots[seat].UpdateScore(roundScore, totalScore);
    }
}
