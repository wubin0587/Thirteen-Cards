// Scripts/UI/TimerView.cs
// 理牌倒计时圆环。订阅 GameEvents.OnTimerTick，更新 Image.fillAmount。

using UnityEngine;
using UnityEngine.UI;

public class TimerView : MonoBehaviour
{
    [Header("UI References")]
    [SerializeField] private Image _ringImage;         // fillMethod = Radial360
    [SerializeField] private Text  _secondsLabel;

    [Header("Colors")]
    [SerializeField] private Color _normalColor  = Color.green;
    [SerializeField] private Color _warningColor = Color.yellow;
    [SerializeField] private Color _urgentColor  = Color.red;

    [SerializeField] [Range(0.1f, 0.5f)]
    private float _warningThreshold = 0.3f;   // 剩余比例低于此值变黄
    [SerializeField] [Range(0.05f, 0.2f)]
    private float _urgentThreshold  = 0.1f;   // 低于此值变红

    private float _totalDuration = 60f;

    // ── 生命周期 ─────────────────────────────────────────────────────────────
    void OnEnable()
    {
        GameEvents.OnTimerStart += HandleTimerStart;
        GameEvents.OnTimerTick  += HandleTimerTick;
    }

    void OnDisable()
    {
        GameEvents.OnTimerStart -= HandleTimerStart;
        GameEvents.OnTimerTick  -= HandleTimerTick;
    }

    // ── 事件处理 ─────────────────────────────────────────────────────────────
    private void HandleTimerStart(float duration)
    {
        _totalDuration = duration;
        UpdateDisplay(duration);
    }

    private void HandleTimerTick(float remaining)
    {
        UpdateDisplay(remaining);
    }

    private void UpdateDisplay(float remaining)
    {
        if (_ringImage == null) return;

        float ratio = _totalDuration > 0 ? remaining / _totalDuration : 0f;
        _ringImage.fillAmount = Mathf.Clamp01(ratio);

        // 颜色过渡
        if (ratio <= _urgentThreshold)
            _ringImage.color = _urgentColor;
        else if (ratio <= _warningThreshold)
            _ringImage.color = _warningColor;
        else
            _ringImage.color = _normalColor;

        // 秒数文字
        if (_secondsLabel != null)
            _secondsLabel.text = Mathf.CeilToInt(remaining).ToString();
    }
}
