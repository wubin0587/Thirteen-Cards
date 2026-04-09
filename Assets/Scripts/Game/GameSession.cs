using System;
using UnityEngine;

public class GameSession : MonoBehaviour
{
    public static GameSession Instance { get; private set; } = null!;

    private IntPtr[] _players = Array.Empty<IntPtr>();
    private IntPtr _handMgr = IntPtr.Zero;

    public RoomConfig Config { get; private set; } = new(0, 0, Array.Empty<SeatConfig>());
    public int[] MyHand { get; private set; } = Array.Empty<int>();
    public GamePhase Phase { get; private set; } = GamePhase.Idle;

    private void Awake()
    {
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }
        Instance = this;
    }

    public void StartRound(RoomConfig cfg)
    {
        Config = cfg;
        Phase = GamePhase.Dealing;

        _players = new IntPtr[cfg.PlayerCount];
        for (var i = 0; i < cfg.PlayerCount; i++)
            _players[i] = TC.tc_player_round_create(cfg.Seats[i].Name);

        TC.tc_round_deal_players(_players, cfg.PlayerCount);

        MyHand = new int[13];
        var rc = TC.tc_player_round_get_hand(_players[0], MyHand);
        if (rc != 0)
            Debug.LogError($"FetchMyHand failed: {rc}");

        _handMgr = TC.tc_hand_manager_create(MyHand);

        Phase = GamePhase.Arranging;
        GameEvents.OnDealDone?.Invoke();
    }

    public bool SelectCard(int idx) => TC.tc_hand_manager_select_card(_handMgr, idx) == 1;
    public bool DeselectCard(int idx) => TC.tc_hand_manager_deselect_card(_handMgr, idx) == 1;
    public bool AddToPile(int pos, int idx) => TC.tc_hand_manager_add_to_pile(_handMgr, pos, idx) == 1;
    public bool RemoveFromPile(int pos, int idx) => TC.tc_hand_manager_remove_from_pile(_handMgr, pos, idx) == 1;
    public bool Undo() => TC.tc_hand_manager_undo(_handMgr) == 1;
    public bool IsPileFull(int pos) => TC.tc_hand_manager_pile_full(_handMgr, pos) == 1;

    public bool SubmitMyHand()
    {
        if (_handMgr == IntPtr.Zero) return false;

        var patternSize = 104;
        var patternPtr = System.Runtime.InteropServices.Marshal.AllocHGlobal(patternSize);
        try
        {
            if (TC.tc_hand_manager_submit(_handMgr, patternPtr) != 1)
                return false;

            // C++ submit 后 pattern 已填充，具体的 position 写入 PlayerRound 由后续协议扩展。
            return true;
        }
        finally
        {
            System.Runtime.InteropServices.Marshal.FreeHGlobal(patternPtr);
        }
    }

    public int[] CloseRound()
    {
        TC.tc_round_close_players(_players, Config.PlayerCount);

        var scores = new int[Config.PlayerCount];
        for (var i = 0; i < Config.PlayerCount; i++)
            scores[i] = TC.tc_player_round_get_round_score(_players[i]);

        CheckAchievements();
        Phase = GamePhase.Done;
        GameEvents.OnRoundDone?.Invoke(scores);
        return scores;
    }

    public int[] GetBotHand(int seat)
    {
        var hand = new int[13];
        TC.tc_player_round_get_hand(_players[seat], hand);
        return hand;
    }

    public void SubmitBotSpecial(int seat)
    {
        Debug.Log($"Seat {seat} submit special hand");
    }

    public void SubmitBotHand(int seat, object combo)
    {
        Debug.Log($"Seat {seat} submit combo {combo}");
    }

    private void CheckAchievements()
    {
        for (var i = 0; i < Config.PlayerCount; i++)
        {
            if (TC.tc_player_round_has_achievement(_players[i], 0) == 1)
                Debug.Log($"Seat {i} unlocked achievement");
        }
    }

    private void OnDestroy()
    {
        if (_handMgr != IntPtr.Zero)
        {
            TC.tc_hand_manager_destroy(_handMgr);
            _handMgr = IntPtr.Zero;
        }

        foreach (var p in _players)
        {
            if (p != IntPtr.Zero)
                TC.tc_player_round_destroy(p);
        }

        _players = Array.Empty<IntPtr>();
    }
}
