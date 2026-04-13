// Scripts/Game/BotRunner.cs
// Bot 决策协程。Easy/Medium 走贪心，Hard/Expert 走 Sentis 模型推理。
// 每个 Bot 在独立协程中决策，并行推进，带难度相关的思考延迟。

using System.Collections;
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;

public class BotRunner : MonoBehaviour
{
    public static BotRunner Instance { get; private set; }

    [SerializeField] private SeatManager _seatManager;

    void Awake()
    {
        if (Instance != null && Instance != this) { Destroy(gameObject); return; }
        Instance = this;
    }

    // ── 外部调用：开始所有 Bot 的决策流程 ────────────────────────────────────
    /// <summary>发牌完成后由 GameScene 调用，所有 Bot 并行开始决策。</summary>
    public void StartAllBots(GameSession session)
    {
        var cfg = session.Config;
        for (int i = 1; i < cfg.PlayerCount; i++)
        {
            if (cfg.Seats[i].Type == SeatType.Bot)
                StartCoroutine(DecideOne(session, i, cfg.Seats[i].Difficulty));
        }
    }

    // ── 单个 Bot 决策协程 ─────────────────────────────────────────────────────
    private IEnumerator DecideOne(GameSession session, int seat, BotDifficulty diff)
    {
        _seatManager?.ShowThinking(seat, true);

        int[] hand = session.GetBotHand(seat);
        if (hand == null)
        {
            Debug.LogError($"[BotRunner] Seat {seat} has no hand.");
            yield break;
        }

        // DFS 枚举（C++ 已实现）
        DFSResult dfs = DFSHelper.Enumerate(hand, maxK: 32);
        if (dfs == null)
        {
            _seatManager?.ShowThinking(seat, false);
            yield break;
        }

        // 特殊牌型直接结算
        if (dfs.IsSpecial)
        {
            float delay = ThinkDelay(diff);
            yield return new WaitForSeconds(delay);
            _seatManager?.ShowThinking(seat, false);
            session.SubmitBotSpecial(seat);
            yield break;
        }

        if (dfs.ComboCount == 0)
        {
            Debug.LogWarning($"[BotRunner] Seat {seat} DFS returned 0 combos.");
            _seatManager?.ShowThinking(seat, false);
            yield break;
        }

        // 选择 combo 索引
        int comboIdx;

        switch (diff)
        {
            case BotDifficulty.Easy:
                // 随机选（DFS 结果不保证顺序，随机模拟菜鸟）
                comboIdx = Random.Range(0, dfs.ComboCount);
                break;

            case BotDifficulty.Medium:
                // DFS 已按 typed_score 降序，选第一个 = 贪心最优
                comboIdx = 0;
                break;

            case BotDifficulty.Hard:
            case BotDifficulty.Expert:
                // 走 Sentis 模型
                Task<int> inferTask = SentisRunner.Instance != null
                    ? SentisRunner.Instance.InferAsync(hand, dfs, diff)
                    : Task.FromResult(0);

                // yield 直到推理完成
                while (!inferTask.IsCompleted)
                    yield return null;

                comboIdx = inferTask.IsFaulted ? 0 : inferTask.Result;
                comboIdx = Mathf.Clamp(comboIdx, 0, dfs.ComboCount - 1);
                break;

            default:
                comboIdx = 0;
                break;
        }

        // 思考延迟（模拟真人）
        float thinkDelay = ThinkDelay(diff);
        yield return new WaitForSeconds(thinkDelay);

        _seatManager?.ShowThinking(seat, false);
        session.SubmitBotHand(seat, dfs.Combos[comboIdx]);
    }

    // ── 思考延迟（秒）────────────────────────────────────────────────────────
    private static float ThinkDelay(BotDifficulty diff) => diff switch
    {
        BotDifficulty.Easy   => Random.Range(1.0f, 2.5f),
        BotDifficulty.Medium => Random.Range(0.8f, 1.5f),
        BotDifficulty.Hard   => Random.Range(0.5f, 1.0f),
        BotDifficulty.Expert => Random.Range(0.3f, 0.7f),
        _                    => 1.0f,
    };
}
