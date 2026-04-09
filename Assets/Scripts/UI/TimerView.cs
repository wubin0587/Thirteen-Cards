using UnityEngine;
using UnityEngine.UI;

public class TimerView : MonoBehaviour
{
    [SerializeField] private Image _ring = null!;
    [SerializeField] private float _duration = 60f;

    private float _left;

    private void OnEnable() => _left = _duration;

    private void Update()
    {
        if (GameSession.Instance == null || GameSession.Instance.Phase != GamePhase.Arranging) return;

        _left = Mathf.Max(0f, _left - Time.deltaTime);
        _ring.fillAmount = _duration <= 0f ? 0f : _left / _duration;
    }
}
