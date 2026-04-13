// Scripts/UI/PileZoneView.cs
// 三墩槽位展示，实时显示牌型名称标签。
// 直接调 C++ tc_search_pattern，不自己判断牌型。

using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.UI;

public class PileZoneView : MonoBehaviour
{
    [Header("Pile Slots (Index 0=头墩 1=中墩 2=尾墩)")]
    [SerializeField] private Transform[] _pileContainers;   // 3 个容器
    [SerializeField] private Text[]      _pileLabels;       // 牌型标签
    [SerializeField] private Text[]      _pileCapacityLabels; // "0/3", "0/5" 提示
    [SerializeField] private Image[]     _pileHighlights;   // 拖入时高亮

    [Header("Card Prefab")]
    [SerializeField] private CardView    _cardViewPrefab;

    // ── 内部状态 ──────────────────────────────────────────────────────────────
    // pileCards[pos] = List of (handCardIdx, cardId)
    private List<(int handIdx, int cardId)>[] _pileCards;
    private CardView[][]                       _pileCardViews;

    private static readonly int[] PILE_CAPACITIES = { 3, 5, 5 };
    private static readonly string[] PILE_NAMES   = { "头墩", "中墩", "尾墩" };

    // ── 初始化 ────────────────────────────────────────────────────────────────
    void Awake()
    {
        _pileCards     = new List<(int, int)>[3];
        _pileCardViews = new CardView[3][];
        for (int i = 0; i < 3; i++)
        {
            _pileCards[i]     = new List<(int, int)>();
            _pileCardViews[i] = new CardView[PILE_CAPACITIES[i]];
        }
        RefreshAllLabels();
    }

    // ── 外部回调：牌加入墩位 ─────────────────────────────────────────────────
    public void OnCardAddedToPile(int handIdx, int position, int cardId)
    {
        if (position < 0 || position > 2) return;
        var list = _pileCards[position];
        if (list.Count >= PILE_CAPACITIES[position]) return;

        list.Add((handIdx, cardId));

        // 在墩位容器内创建一张牌的视觉副本
        if (_cardViewPrefab != null && _pileContainers[position] != null)
        {
            int slot = list.Count - 1;
            var cv = Instantiate(_cardViewPrefab, _pileContainers[position]);
            cv.Init(cardId, faceUp: true);
            _pileCardViews[position][slot] = cv;
        }

        RefreshLabel(position);
        RefreshCapacityLabel(position);
    }

    // ── 外部回调：牌从墩位移出 ───────────────────────────────────────────────
    public void OnCardRemovedFromPile(int handIdx, int position)
    {
        if (position < 0 || position > 2) return;
        var list = _pileCards[position];

        int removeIdx = list.FindIndex(x => x.handIdx == handIdx);
        if (removeIdx < 0) return;

        list.RemoveAt(removeIdx);

        // 销毁对应视觉副本
        if (_pileCardViews[position][removeIdx] != null)
        {
            Destroy(_pileCardViews[position][removeIdx].gameObject);
            _pileCardViews[position][removeIdx] = null;
        }

        // 重排视觉
        RearrangeSlot(position);
        RefreshLabel(position);
        RefreshCapacityLabel(position);
    }

    // ── 清空所有墩位 ─────────────────────────────────────────────────────────
    public void ClearAll()
    {
        for (int pos = 0; pos < 3; pos++)
        {
            _pileCards[pos].Clear();
            foreach (Transform t in _pileContainers[pos]) Destroy(t.gameObject);
            for (int i = 0; i < PILE_CAPACITIES[pos]; i++) _pileCardViews[pos][i] = null;
        }
        RefreshAllLabels();
    }

    // ── 牌型标签刷新（直接问 C++）────────────────────────────────────────────
    public void RefreshLabel(int position)
    {
        if (_pileLabels == null || position >= _pileLabels.Length) return;
        if (_pileLabels[position] == null) return;

        var list = _pileCards[position];
        int required = PILE_CAPACITIES[position];

        if (list.Count < required)
        {
            _pileLabels[position].text = PILE_NAMES[position];
            return;
        }

        // 收集牌号
        int[] cards = new int[required];
        for (int i = 0; i < required; i++) cards[i] = list[i].cardId;

        // 直接问 C++，不自己判断
        var result = TC.tc_search_pattern(position, cards, required);
        _pileLabels[position].text = result.HandName;
    }

    private void RefreshAllLabels()
    {
        for (int i = 0; i < 3; i++) RefreshLabel(i);
        for (int i = 0; i < 3; i++) RefreshCapacityLabel(i);
    }

    private void RefreshCapacityLabel(int position)
    {
        if (_pileCapacityLabels == null || position >= _pileCapacityLabels.Length) return;
        if (_pileCapacityLabels[position] == null) return;
        _pileCapacityLabels[position].text =
            $"{_pileCards[position].Count}/{PILE_CAPACITIES[position]}";
    }

    private void RearrangeSlot(int position)
    {
        // 重新紧凑排列（将 null 补到末尾）
        var cv = _pileCardViews[position];
        int write = 0;
        for (int read = 0; read < PILE_CAPACITIES[position]; read++)
        {
            if (cv[read] != null)
            {
                cv[write] = cv[read];
                if (read != write) cv[read] = null;
                write++;
            }
        }
    }

    // ── 拖入高亮（供 DropHandler 调用）──────────────────────────────────────
    public void SetHighlight(int position, bool on)
    {
        if (_pileHighlights == null || position >= _pileHighlights.Length) return;
        if (_pileHighlights[position] != null)
            _pileHighlights[position].gameObject.SetActive(on);
    }

    // ── 查询 ─────────────────────────────────────────────────────────────────
    public bool IsFull(int position) =>
        _pileCards[position].Count >= PILE_CAPACITIES[position];

    public int CardCount(int position) =>
        _pileCards[position].Count;
}
