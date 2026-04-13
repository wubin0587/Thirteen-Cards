// Scripts/UI/CardView.cs
// 单张牌的视觉组件：正/背面切换、选中高亮、变灰（已打出后）。
// 不含任何游戏逻辑，只响应外部调用改变外观。

using System;
using UnityEngine;
using UnityEngine.UI;

public class CardView : MonoBehaviour
{
    [Header("Visual References")]
    [SerializeField] private Image    _frontImage;     // 正面贴图
    [SerializeField] private Image    _backImage;      // 背面贴图
    [SerializeField] private Image    _selectionFrame; // 选中时的发光边框
    [SerializeField] private Image    _greyOverlay;    // 变灰遮罩

    [Header("Animation")]
    [SerializeField] private Animator _animator;       // 可选：翻牌动画

    // ── 公共状态 ─────────────────────────────────────────────────────────────
    public int  CardId     { get; private set; } = -1;
    public bool FaceUp     { get; private set; }
    public bool IsSelected { get; private set; }
    public bool IsGrey     { get; private set; }

    private static readonly int ANIM_FLIP = Animator.StringToHash("Flip");

    // ── 初始化 ────────────────────────────────────────────────────────────────
    public void Init(int cardId, bool faceUp = true)
    {
        CardId = cardId;
        SetFaceUp(faceUp, animate: false);
        SetSelected(false);
        SetGrey(false);
    }

    // ── 正/背面 ───────────────────────────────────────────────────────────────
    public void SetFaceUp(bool faceUp, bool animate = true)
    {
        FaceUp = faceUp;

        if (animate && _animator != null)
        {
            _animator.SetTrigger(ANIM_FLIP);
        }
        else
        {
            ApplyFaceState(faceUp);
        }
    }

    private void ApplyFaceState(bool faceUp)
    {
        if (_frontImage != null) _frontImage.gameObject.SetActive(faceUp);
        if (_backImage  != null) _backImage.gameObject.SetActive(!faceUp);

        if (faceUp && _frontImage != null)
        {
            var sprite = CardDatabase.Instance?.GetSprite(CardId);
            if (sprite != null) _frontImage.sprite = sprite;
        }
    }

    // 动画事件回调（由 Animator 在翻牌中点调用）
    public void OnFlipMidpoint()
    {
        ApplyFaceState(FaceUp);
    }

    // ── 选中状态 ──────────────────────────────────────────────────────────────
    public void SetSelected(bool selected)
    {
        IsSelected = selected;
        if (_selectionFrame != null)
            _selectionFrame.gameObject.SetActive(selected);

        // 选中时小幅上移
        var rt = GetComponent<RectTransform>();
        if (rt != null)
        {
            float yOffset = selected ? 12f : 0f;
            rt.anchoredPosition = new Vector2(rt.anchoredPosition.x, yOffset);
        }
    }

    // ── 变灰（已打出）──────────────────────────────────────────────────────────
    public void SetGrey(bool grey)
    {
        IsGrey = grey;
        if (_greyOverlay != null)
            _greyOverlay.gameObject.SetActive(grey);
    }

    // ── 移动到墩位（视觉上位移，实际 RectTransform 由父级管理）──────────────
    public void MoveToPile(int pilePosition)
    {
        // 由 HandAreaView 负责实际 Re-parent；
        // 这里只触发一个可选的滑动动画提示
        if (_animator != null)
            _animator.SetTrigger("MoveToPile");
    }
}
