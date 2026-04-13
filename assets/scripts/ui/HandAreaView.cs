// Scripts/UI/HandAreaView.cs
// 本机手牌区：13张牌横排，支持触摸选牌与拖拽放墩。
// 原则：所有合法性由 C++ (GameSession) 判断，返回 false 则不更新视图。

using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

public class HandAreaView : MonoBehaviour
{
    [Header("References")]
    [SerializeField] private Transform   _cardContainer;    // 手牌排列容器
    [SerializeField] private CardView    _cardViewPrefab;

    [Header("Layout")]
    [SerializeField] private float _cardSpacing = 55f;      // 每张牌水平间距（像素）
    [SerializeField] private float _selectedYOffset = 16f;  // 选中时上移量

    // ── 运行时状态 ────────────────────────────────────────────────────────────
    private CardView[]  _cardViews;
    private bool[]      _selected;
    private bool[]      _inPile;       // 已放入某墩
    private int[]       _cardIds;

    private PileZoneView _pileZone;    // 由外部注入

    // ── 初始化 ────────────────────────────────────────────────────────────────
    public void Init(int[] hand13, PileZoneView pileZone)
    {
        _pileZone = pileZone;
        _cardIds  = hand13;

        // 清除旧牌
        foreach (Transform t in _cardContainer) Destroy(t.gameObject);

        _cardViews = new CardView[13];
        _selected  = new bool[13];
        _inPile    = new bool[13];

        for (int i = 0; i < 13; i++)
        {
            var cv = Instantiate(_cardViewPrefab, _cardContainer);
            cv.Init(hand13[i], faceUp: true);
            cv.name = $"Card_{i}";

            // 点击事件
            int idx = i;
            var btn = cv.GetComponent<Button>() ?? cv.gameObject.AddComponent<Button>();
            btn.onClick.AddListener(() => OnCardTapped(idx));

            // 拖拽事件（通过 EventTrigger）
            SetupDrag(cv.gameObject, idx);

            _cardViews[i] = cv;
        }

        LayoutCards();
    }

    // ── 卡牌水平排布 ─────────────────────────────────────────────────────────
    private void LayoutCards()
    {
        float totalWidth = (_cardIds.Length - 1) * _cardSpacing;
        float startX     = -totalWidth * 0.5f;

        for (int i = 0; i < _cardViews.Length; i++)
        {
            if (_cardViews[i] == null) continue;
            var rt = _cardViews[i].GetComponent<RectTransform>();
            float yPos = _selected[i] ? _selectedYOffset : 0f;
            rt.anchoredPosition = new Vector2(startX + i * _cardSpacing, yPos);
        }
    }

    // ── 点击选牌 ─────────────────────────────────────────────────────────────
    private void OnCardTapped(int idx)
    {
        if (_inPile[idx]) return;  // 已放入墩位，不可再选

        bool ok;
        if (_selected[idx])
        {
            ok = GameSession.Instance.DeselectCard(idx);
            if (ok) _selected[idx] = false;
        }
        else
        {
            ok = GameSession.Instance.SelectCard(idx);
            if (ok) _selected[idx] = true;
        }

        if (ok)
        {
            _cardViews[idx].SetSelected(_selected[idx]);
            LayoutCards();
        }
    }

    // ── 拖拽放入墩位 ─────────────────────────────────────────────────────────
    private void OnCardDroppedToPile(int cardIdx, int pilePosition)
    {
        if (_inPile[cardIdx]) return;

        bool ok = GameSession.Instance.AddToPile(pilePosition, cardIdx);
        if (!ok) return;

        _inPile[cardIdx]  = true;
        _selected[cardIdx] = false;
        _cardViews[cardIdx].SetGrey(true);
        _cardViews[cardIdx].MoveToPile(pilePosition);
        _pileZone?.OnCardAddedToPile(cardIdx, pilePosition, _cardIds[cardIdx]);
        LayoutCards();
    }

    private void OnCardRemovedFromPile(int cardIdx, int pilePosition)
    {
        bool ok = GameSession.Instance.RemoveFromPile(pilePosition, cardIdx);
        if (!ok) return;

        _inPile[cardIdx]  = false;
        _cardViews[cardIdx].SetGrey(false);
        _pileZone?.OnCardRemovedFromPile(cardIdx, pilePosition);
        LayoutCards();
    }

    // ── EventTrigger 拖拽设置 ────────────────────────────────────────────────
    private void SetupDrag(GameObject go, int idx)
    {
        var et = go.GetComponent<EventTrigger>() ?? go.AddComponent<EventTrigger>();

        // 拖拽进入墩位检测由 PileZoneView 处理（通过 DropHandler）
        // 这里只设置 BeginDrag / EndDrag 供动画使用
        AddTrigger(et, EventTriggerType.BeginDrag, _ =>
        {
            if (!_inPile[idx]) _cardViews[idx].transform.SetAsLastSibling();
        });
    }

    private void AddTrigger(EventTrigger et, EventTriggerType type,
                             UnityEngine.Events.UnityAction<BaseEventData> action)
    {
        var entry = new EventTrigger.Entry { eventID = type };
        entry.callback.AddListener(action);
        et.triggers.Add(entry);
    }

    // ── 外部调用：AI 一键理牌应用 ────────────────────────────────────────────
    /// <summary>将指定墩位分配应用到视图（由 ActionBarView 调用）。</summary>
    public void ApplyAIAssignment(int[] head, int[] middle, int[] tail)
    {
        // 先清空所有墩位的视觉状态
        for (int i = 0; i < 13; i++)
        {
            if (_inPile[i])
            {
                _inPile[i]    = false;
                _cardViews[i].SetGrey(false);
            }
            if (_selected[i])
            {
                _selected[i] = false;
                _cardViews[i].SetSelected(false);
            }
        }

        _pileZone?.ClearAll();

        // 按墩位分配放牌（转换为手牌 index）
        ApplyGroup(head,   0);
        ApplyGroup(middle, 1);
        ApplyGroup(tail,   2);

        LayoutCards();
    }

    private void ApplyGroup(int[] cards, int pilePos)
    {
        foreach (int cardId in cards)
        {
            int idx = FindHandIndex(cardId);
            if (idx < 0) continue;
            OnCardDroppedToPile(idx, pilePos);
        }
    }

    private int FindHandIndex(int cardId)
    {
        for (int i = 0; i < _cardIds.Length; i++)
            if (_cardIds[i] == cardId && !_inPile[i]) return i;
        return -1;
    }

    // ── PileZoneView 回调：从墩位移出 ────────────────────────────────────────
    public void NotifyRemoveFromPile(int cardIdx, int pilePos)
    {
        OnCardRemovedFromPile(cardIdx, pilePos);
    }
}
