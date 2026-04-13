// Scripts/Game/GameSession.cs
// 核心游戏驱动。持有所有 PlayerRound / HandManager 的 C++ 句柄，
// 驱动状态机，是其他组件唯一的数据来源。
// 状态：Idle → Dealing → Arranging → Revealing → Done

using System;
using System.Collections;
using System.Runtime.InteropServices;
using UnityEngine;

public enum GamePhase
{
    Idle,
    Dealing,
    Arranging,
    Revealing,
    Done,
}

public class GameSession : MonoBehaviour
{
    public static GameSession Instance { get; private set; }

    // ── 公共只读状态 ─────────────────────────────────────────────────────────
    public RoomConfig Config  { get; private set; }
    public int[]      MyHand  { get; private set; }   // 本机 13 张 cardId
    public GamePhase  Phase   { get; private set; } = GamePhase.Idle;
    public float      TimeLeft { get; private set; }

    [Header("Arrange Phase Settings")]
    [SerializeField] private float arrangeDuration = 60f;

    // ── 内部 C++ 句柄 ─────────────────────────────────────────────────────────
    private IntPtr[] _players;    // tc_player_round_t[]
    private IntPtr   _handMgr;    // tc_hand_manager_t，本机专用

    // ── 本机 Bot 手牌缓存（bot seat → hand13）───────────────────────────────
    private int[][] _botHands;

    // ── 结算缓存 ──────────────────────────────────────────────────────────────
    private int[] _lastScores;

    // ─────────────────────────────────────────────────────────────────────────
    void Awake()
    {
        if (Instance != null && Instance != this) { Destroy(gameObject); return; }
        Instance = this;
        DontDestroyOnLoad(gameObject);
    }

    void OnDestroy()
    {
        FreeHandles();
    }

    // ── 一局开始 ──────────────────────────────────────────────────────────────
    /// <summary>
    /// 外部（RoomSetupView 或测试代码）调用此方法启动一局。
    /// </summary>
    public void StartRound(RoomConfig cfg)
    {
        FreeHandles();   // 清理上一局残留句柄

        Config = cfg;
        Phase  = GamePhase.Dealing;

        int n = cfg.PlayerCount;
        _players  = new IntPtr[n];
        _botHands = new int[n][];

        // 创建所有 PlayerRound
        for (int i = 0; i < n; i++)
            _players[i] = TC.tc_player_round_create(cfg.Seats[i].Name);

        // C++ 内部洗牌并发牌
        int rc = TC.tc_round_deal_players(_players, n);
        if (rc != RoundError.Ok)
        {
            Debug.LogError($"[GameSession] tc_round_deal_players error {rc}");
            Phase = GamePhase.Idle;
            return;
        }

        // 取回各玩家手牌
        for (int i = 0; i < n; i++)
        {
            var hand = new int[13];
            TC.tc_player_round_get_hand(_players[i], hand);
            _botHands[i] = hand;
        }

        // 本机玩家固定为 seat 0
        MyHand   = _botHands[0];
        _handMgr = TC.tc_hand_manager_create(MyHand);

        Phase = GamePhase.Arranging;
        GameEvents.FireDealDone();
        StartCoroutine(ArrangeCountdown());
    }

    // ── 倒计时协程 ───────────────────────────────────────────────────────────
    private IEnumerator ArrangeCountdown()
    {
        TimeLeft = arrangeDuration;
        GameEvents.FireTimerStart(arrangeDuration);

        while (TimeLeft > 0f && Phase == GamePhase.Arranging)
        {
            yield return null;
            TimeLeft -= Time.deltaTime;
            GameEvents.FireTimerTick(Mathf.Max(TimeLeft, 0f));
        }

        if (Phase == GamePhase.Arranging)
        {
            // 时间到，强制提交（未提交的玩家视为倒水）
            Debug.Log("[GameSession] Arrange timer expired, force submit.");
            SubmitMyHand();
        }
    }

    // ── 本机玩家操作（直接透传 C++ HandManager）─────────────────────────────
    // 返回 false → C++ 判定非法，UI 不刷新

    public bool SelectCard(int idx)
    {
        bool ok = TC.tc_hand_manager_select_card(_handMgr, idx) == 1;
        if (ok) GameEvents.FireCardSelectionChanged(idx, true);
        return ok;
    }

    public bool DeselectCard(int idx)
    {
        bool ok = TC.tc_hand_manager_deselect_card(_handMgr, idx) == 1;
        if (ok) GameEvents.FireCardSelectionChanged(idx, false);
        return ok;
    }

    public bool AddToPile(int position, int cardIdx)
    {
        bool ok = TC.tc_hand_manager_add_to_pile(_handMgr, position, cardIdx) == 1;
        if (ok) GameEvents.FirePileChanged(position);
        return ok;
    }

    public bool RemoveFromPile(int position, int cardIdx)
    {
        bool ok = TC.tc_hand_manager_remove_from_pile(_handMgr, position, cardIdx) == 1;
        if (ok) GameEvents.FirePileChanged(position);
        return ok;
    }

    public bool Undo()
    {
        return TC.tc_hand_manager_undo(_handMgr) == 1;
    }

    public bool IsPileFull(int position)
    {
        return TC.tc_hand_manager_pile_full(_handMgr, position) == 1;
    }

    // ── 本机提交三墩 ─────────────────────────────────────────────────────────
    public bool SubmitMyHand()
    {
        if (Phase != GamePhase.Arranging) return false;

        // 分配 Pattern 结构体非托管内存，让 C++ 填写内容
        // Pattern 大小：约 (3 + 3*5 + 3*5)*4 = 108 bytes，保守给 512
        IntPtr patPtr = Marshal.AllocHGlobal(512);
        try
        {
            // 清零
            for (int i = 0; i < 512; i++) Marshal.WriteByte(patPtr, i, 0);
            TC.tc_pattern_init(MyHand, patPtr);

            int rc = TC.tc_hand_manager_submit(_handMgr, patPtr);
            if (rc != 1)
            {
                Debug.LogWarning("[GameSession] HandManager submit failed (foul or incomplete).");
                return false;
            }

            // 将三墩写入本机 PlayerRound
            WritePatternToPlayerRound(patPtr, 0);
        }
        finally
        {
            Marshal.FreeHGlobal(patPtr);
        }

        GameEvents.FireMyHandSubmitted();
        CheckAllSubmitted();
        return true;
    }

    // ── Bot 提交三墩 ─────────────────────────────────────────────────────────
    /// <summary>BotRunner 调用，为指定座位提交墩位分配。</summary>
    public void SubmitBotHand(int seat, HandComboManaged combo)
    {
        if (seat < 1 || seat >= Config.PlayerCount) return;

        var dfsResult = new DFSResult { Combos = new[] { combo }, ComboCount = 1 };
        if (!dfsResult.AssignPositions(0,
                out int[] head, out int[] middle, out int[] tail))
        {
            Debug.LogWarning($"[GameSession] Bot seat {seat} foul (invalid assignment).");
            // 倒水：不设置任何墩位，C++ settle 会判定倒水
            return;
        }

        TC.tc_player_round_set_position(_players[seat], 0, head,   3);
        TC.tc_player_round_set_position(_players[seat], 1, middle, 5);
        TC.tc_player_round_set_position(_players[seat], 2, tail,   5);

        CheckAllSubmitted();
    }

    public void SubmitBotSpecial(int seat)
    {
        // 特殊牌型不需要 set_position，直接 settle 时 C++ 会处理
        CheckAllSubmitted();
    }

    // ── 获取 Bot 手牌（供 BotRunner 读取）────────────────────────────────────
    public int[] GetBotHand(int seat)
    {
        if (seat < 0 || seat >= _botHands.Length) return null;
        return _botHands[seat];
    }

    // ── 全员提交检测 → 进入翻牌阶段 ─────────────────────────────────────────
    private int _submittedCount = 0;

    private void CheckAllSubmitted()
    {
        _submittedCount++;
        if (_submittedCount >= Config.PlayerCount)
        {
            _submittedCount = 0;
            Phase = GamePhase.Revealing;
            GameEvents.FireRevealStart();
            CloseRound();
        }
    }

    // ── 结算 ─────────────────────────────────────────────────────────────────
    private void CloseRound()
    {
        int rc = TC.tc_round_close_players(_players, Config.PlayerCount);
        if (rc != RoundError.Ok)
            Debug.LogWarning($"[GameSession] tc_round_close_players returned {rc}");

        int n = Config.PlayerCount;
        _lastScores = new int[n];
        for (int i = 0; i < n; i++)
            _lastScores[i] = TC.tc_player_round_get_round_score(_players[i]);

        CheckAchievements();

        Phase = GamePhase.Done;
        GameEvents.FireRoundDone(_lastScores);
    }

    private void CheckAchievements()
    {
        for (int i = 0; i < Config.PlayerCount; i++)
        {
            if (TC.tc_player_round_has_achievement(_players[i], (int)Achievement.Homerun) == 1)
                GameEvents.FireHomerun(i);
            else if (TC.tc_player_round_has_achievement(_players[i], (int)Achievement.Shoot) == 1)
                GameEvents.FireShoot(i);
        }
    }

    // ── 辅助：将 Pattern 写入 PlayerRound ─────────────────────────────────────
    private void WritePatternToPlayerRound(IntPtr patPtr, int seat)
    {
        int[] buf = new int[5];

        // 头墩（3张）
        int cnt = TC.tc_pattern_get_position(patPtr, 0, buf);
        if (cnt == 3)
        {
            int[] head = new int[3];
            Array.Copy(buf, head, 3);
            TC.tc_player_round_set_position(_players[seat], 0, head, 3);
        }

        // 中墩（5张）
        cnt = TC.tc_pattern_get_position(patPtr, 1, buf);
        if (cnt == 5)
        {
            int[] mid = new int[5];
            Array.Copy(buf, mid, 5);
            TC.tc_player_round_set_position(_players[seat], 1, mid, 5);
        }

        // 尾墩（5张）
        cnt = TC.tc_pattern_get_position(patPtr, 2, buf);
        if (cnt == 5)
        {
            int[] tail = new int[5];
            Array.Copy(buf, tail, 5);
            TC.tc_player_round_set_position(_players[seat], 2, tail, 5);
        }
    }

    // ── 查询接口 ─────────────────────────────────────────────────────────────
    public int GetLastScore(int seat) =>
        _lastScores != null && seat < _lastScores.Length ? _lastScores[seat] : 0;

    public int GetTotalScore(int seat) =>
        seat < Config.PlayerCount
            ? TC.tc_player_round_get_total_score(_players[seat])
            : 0;

    // ── 内存释放 ─────────────────────────────────────────────────────────────
    private void FreeHandles()
    {
        if (_handMgr != IntPtr.Zero)
        {
            TC.tc_hand_manager_destroy(_handMgr);
            _handMgr = IntPtr.Zero;
        }
        if (_players != null)
        {
            foreach (var p in _players)
                if (p != IntPtr.Zero) TC.tc_player_round_destroy(p);
            _players = null;
        }
        _submittedCount = 0;
    }
}
