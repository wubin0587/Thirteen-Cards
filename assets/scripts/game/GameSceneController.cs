// Scripts/Game/GameSceneController.cs
// Game 场景总协调器：在 Awake/Start 把所有组件串联起来，
// 监听 GameEvents 驱动 UI 和 Bot 流程。

using UnityEngine;
using UnityEngine.UI;

public class GameSceneController : MonoBehaviour
{
    [Header("Core Components")]
    [SerializeField] private SeatManager   _seatManager;
    [SerializeField] private BotRunner     _botRunner;

    [Header("Local Player UI")]
    [SerializeField] private HandAreaView  _handAreaView;
    [SerializeField] private PileZoneView  _pileZoneView;
    [SerializeField] private ActionBarView _actionBarView;
    [SerializeField] private TimerView     _timerView;

    [Header("Result")]
    [SerializeField] private ResultView    _resultView;

    [Header("Reveal Panel")]
    [SerializeField] private GameObject    _revealPanel;   // 翻牌阶段展示面板

    // ── 初始化 ────────────────────────────────────────────────────────────────
    void OnEnable()
    {
        GameEvents.OnDealDone        += HandleDealDone;
        GameEvents.OnRevealStart     += HandleRevealStart;
        GameEvents.OnRoundDone       += HandleRoundDone;
    }

    void OnDisable()
    {
        GameEvents.OnDealDone        -= HandleDealDone;
        GameEvents.OnRevealStart     -= HandleRevealStart;
        GameEvents.OnRoundDone       -= HandleRoundDone;
    }

    // ── 发牌完成：初始化所有视图，启动 Bot ────────────────────────────────────
    private void HandleDealDone()
    {
        var session = GameSession.Instance;
        if (session == null) return;

        // 初始化座位布局
        _seatManager?.Setup(session.Config);

        // 初始化本机手牌区
        _handAreaView?.Init(session.MyHand, _pileZoneView);

        // 启动所有 Bot 决策协程
        _botRunner?.StartAllBots(session);
    }

    // ── 翻牌阶段：显示所有玩家的牌 ────────────────────────────────────────────
    private void HandleRevealStart()
    {
        if (_revealPanel != null)
            _revealPanel.SetActive(true);
    }

    // ── 结算完成：更新所有水数显示 ────────────────────────────────────────────
    private void HandleRoundDone(int[] scores)
    {
        var session = GameSession.Instance;
        if (session == null) return;

        int n = session.Config.PlayerCount;
        for (int i = 0; i < n; i++)
        {
            int total = session.GetTotalScore(i);
            _seatManager?.UpdateScore(i, scores[i], total);
        }
        // ResultView 通过自己订阅 OnRoundDone 显示排名面板
    }
}
