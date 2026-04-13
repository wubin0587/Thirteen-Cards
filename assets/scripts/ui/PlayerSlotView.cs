// Scripts/UI/PlayerSlotView.cs
// 对手（或本机）头像槽位：名字、水数、思考动画、成就特效接入。

using UnityEngine;
using UnityEngine.UI;

public class PlayerSlotView : MonoBehaviour
{
    [Header("UI References")]
    [SerializeField] private Text  _nameLabel;
    [SerializeField] private Text  _roundScoreLabel;
    [SerializeField] private Text  _totalScoreLabel;
    [SerializeField] private Image _avatarImage;
    [SerializeField] private Image _myIndicator;      // 本机专用标记

    [Header("Thinking Indicator")]
    [SerializeField] private GameObject _thinkingSpinner;  // 旋转动画对象

    [Header("Achievement FX")]
    [SerializeField] private Animator _achievementAnimator;
    private static readonly int ANIM_SHOOT   = Animator.StringToHash("Shoot");
    private static readonly int ANIM_HOMERUN = Animator.StringToHash("Homerun");

    [Header("Avatar Sprites")]
    [SerializeField] private Sprite[] _botAvatars;      // 按难度索引 0~3
    [SerializeField] private Sprite   _humanAvatar;

    // ── 内部状态 ──────────────────────────────────────────────────────────────
    private int _seatIndex;

    // ── 初始化 ────────────────────────────────────────────────────────────────
    public void Init(SeatConfig cfg, bool isMySlot)
    {
        _seatIndex = cfg.SeatIndex;

        if (_nameLabel != null)
            _nameLabel.text = cfg.Name;

        if (_myIndicator != null)
            _myIndicator.gameObject.SetActive(isMySlot);

        if (_avatarImage != null)
        {
            if (cfg.Type == SeatType.Human)
                _avatarImage.sprite = _humanAvatar;
            else if (_botAvatars != null && (int)cfg.Difficulty < _botAvatars.Length)
                _avatarImage.sprite = _botAvatars[(int)cfg.Difficulty];
        }

        UpdateScore(0, 0);
        SetThinking(false);

        // 订阅成就事件
        GameEvents.OnShoot   += HandleShoot;
        GameEvents.OnHomerun += HandleHomerun;
    }

    void OnDestroy()
    {
        GameEvents.OnShoot   -= HandleShoot;
        GameEvents.OnHomerun -= HandleHomerun;
    }

    // ── 分数更新 ─────────────────────────────────────────────────────────────
    public void UpdateScore(int roundScore, int totalScore)
    {
        if (_roundScoreLabel != null)
        {
            string sign = roundScore >= 0 ? "+" : "";
            _roundScoreLabel.text = $"{sign}{roundScore}";
            _roundScoreLabel.color = roundScore >= 0 ? Color.yellow : Color.red;
        }

        if (_totalScoreLabel != null)
            _totalScoreLabel.text = $"{totalScore}";
    }

    // ── 思考动画 ─────────────────────────────────────────────────────────────
    public void SetThinking(bool thinking)
    {
        if (_thinkingSpinner != null)
            _thinkingSpinner.SetActive(thinking);
    }

    // ── 成就特效 ─────────────────────────────────────────────────────────────
    private void HandleShoot(int seat)
    {
        if (seat != _seatIndex) return;
        _achievementAnimator?.SetTrigger(ANIM_SHOOT);
    }

    private void HandleHomerun(int seat)
    {
        if (seat != _seatIndex) return;
        _achievementAnimator?.SetTrigger(ANIM_HOMERUN);
    }
}
