using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;

public class BotRunner : MonoBehaviour
{
    public async Task DecideAllAsync(GameSession session)
    {
        var tasks = new List<Task>();
        var cfg = session.Config;
        for (var i = 1; i < cfg.PlayerCount; i++)
        {
            if (cfg.Seats[i].Type != SeatType.Bot) continue;
            tasks.Add(DecideOneAsync(session, i, cfg.Seats[i].Difficulty));
        }
        await Task.WhenAll(tasks);
    }

    private async Task DecideOneAsync(GameSession session, int seat, BotDifficulty diff)
    {
        var hand = session.GetBotHand(seat);
        var dfs = DFSHelper.Enumerate(hand, maxK: 32);
        if (dfs.IsSpecial)
        {
            session.SubmitBotSpecial(seat);
            return;
        }

        int idx = diff switch
        {
            BotDifficulty.Easy => Random.Range(0, dfs.ComboCount),
            BotDifficulty.Medium => 0,
            _ => await SentisRunner.Instance.InferAsync(hand, dfs, diff)
        };

        await Task.Delay((int)(ThinkDelay(diff) * 1000));
        session.SubmitBotHand(seat, dfs.Combos[idx]);
    }

    private static float ThinkDelay(BotDifficulty d) => d switch
    {
        BotDifficulty.Easy => Random.Range(1f, 2.5f),
        BotDifficulty.Medium => Random.Range(0.8f, 1.5f),
        BotDifficulty.Hard => Random.Range(0.5f, 1f),
        BotDifficulty.Expert => Random.Range(0.3f, 0.7f),
        _ => 1f
    };
}

public sealed class DFSResult
{
    public bool IsSpecial { get; init; }
    public int ComboCount => Combos.Count;
    public List<object> Combos { get; } = new();
}

public static class DFSHelper
{
    public static DFSResult Enumerate(int[] hand, int maxK)
    {
        _ = hand;
        _ = maxK;
        var result = new DFSResult { IsSpecial = false };
        result.Combos.Add(new object());
        return result;
    }
}
