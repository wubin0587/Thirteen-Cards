// Scripts/UI/ActionBarView.cs
// 操作栏：一键理牌 / 撤销 / 提交三个按钮。

using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.UI;

public class ActionBarView : MonoBehaviour
{
    [Header("Buttons")]
    [SerializeField] private Button _aiButton;      // ⚡ 一键理牌
    [SerializeField] private Button _undoButton;    // ↩ 撤销
    [SerializeField] private Button _submitButton;  // ✓ 提交

    [Header("References")]
    [SerializeField] private HandAreaView _handAreaView;
    [SerializeField] private PileZoneView _pileZoneView;

    [Header("Button Labels")]
    [SerializeField] private Text _aiButtonLabel;

    private bool _submitted = false;
    private bool _aiRunning = false;

    // ── 初始化 ────────────────────────────────────────────────────────────────
    void Awake()
    {
        _aiButton?.onClick.AddListener(OnAIRecommend);
        _undoButton?.onClick.AddListener(OnUndo);
        _submitButton?.onClick.AddListener(OnSubmit);
    }

    void OnEnable()
    {
        GameEvents.OnMyHandSubmitted += HandleSubmitted;
    }

    void OnDisable()
    {
        GameEvents.OnMyHandSubmitted -= HandleSubmitted;
    }

    // ── 一键理牌 ─────────────────────────────────────────────────────────────
    private async void OnAIRecommend()
    {
        if (_aiRunning || _submitted) return;
        if (SentisRunner.Instance == null)
        {
            Debug.LogWarning("[ActionBarView] SentisRunner not available.");
            return;
        }

        _aiRunning = true;
        SetButtonsInteractable(false);
        if (_aiButtonLabel != null) _aiButtonLabel.text = "推理中…";

        int[] hand13 = GameSession.Instance?.MyHand;
        if (hand13 == null) { _aiRunning = false; SetButtonsInteractable(true); return; }

        DFSResult dfs = DFSHelper.Enumerate(hand13, maxK: 64);
        if (dfs == null || dfs.IsSpecial || dfs.ComboCount == 0)
        {
            _aiRunning = false;
            SetButtonsInteractable(true);
            return;
        }

        int comboIdx = await SentisRunner.Instance.RecommendAsync(hand13, dfs);
        comboIdx = Mathf.Clamp(comboIdx, 0, dfs.ComboCount - 1);

        // 检查墩位分配是否合法
        if (!dfs.AssignPositions(comboIdx,
                out int[] head, out int[] middle, out int[] tail))
        {
            // fallback：找第一个合法的
            for (int i = 0; i < dfs.ComboCount; i++)
            {
                if (dfs.AssignPositions(i, out head, out middle, out tail))
                    break;
            }
        }

        _handAreaView?.ApplyAIAssignment(head, middle, tail);

        if (_aiButtonLabel != null) _aiButtonLabel.text = "⚡ 一键理牌";
        _aiRunning = false;
        SetButtonsInteractable(true);
    }

    // ── 撤销 ─────────────────────────────────────────────────────────────────
    private void OnUndo()
    {
        if (_submitted) return;
        bool ok = GameSession.Instance?.Undo() ?? false;
        // 撤销成功时 GameEvents.OnPileChanged 会通知 PileZoneView 刷新
        // HandAreaView 通过 GameEvents.OnCardSelectionChanged 同步
    }

    // ── 提交 ─────────────────────────────────────────────────────────────────
    private void OnSubmit()
    {
        if (_submitted) return;

        // 检查三墩是否都填满
        if (_pileZoneView != null)
        {
            if (!_pileZoneView.IsFull(0) || !_pileZoneView.IsFull(1) || !_pileZoneView.IsFull(2))
            {
                Debug.Log("[ActionBarView] Cannot submit: piles not full.");
                // TODO: 显示提示 UI
                return;
            }
        }

        bool ok = GameSession.Instance?.SubmitMyHand() ?? false;
        if (!ok)
            Debug.LogWarning("[ActionBarView] SubmitMyHand failed (foul or incomplete).");
    }

    private void HandleSubmitted()
    {
        _submitted = true;
        SetButtonsInteractable(false);
    }

    private void SetButtonsInteractable(bool on)
    {
        if (_aiButton     != null) _aiButton.interactable     = on && !_submitted;
        if (_undoButton   != null) _undoButton.interactable   = on && !_submitted;
        if (_submitButton != null) _submitButton.interactable = on && !_submitted;
    }
}
