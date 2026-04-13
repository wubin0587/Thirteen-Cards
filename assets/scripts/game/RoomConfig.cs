// Scripts/Game/RoomConfig.cs
// 房间和座位的纯数据结构。C# 侧唯一两个业务数据类。

public enum SeatType
{
    Human,
    Bot,
}

public enum BotDifficulty
{
    Easy,
    Medium,
    Hard,
    Expert,
}

public record SeatConfig(
    int           SeatIndex,
    SeatType      Type,
    BotDifficulty Difficulty,
    string        Name
);

public record RoomConfig(
    int          PlayerCount,   // 3~12
    int          DeckCount,     // <=4→1, <=8→2, <=12→3
    SeatConfig[] Seats
)
{
    /// <summary>根据玩家数量计算应使用的牌副数。</summary>
    public static int CalcDeckCount(int playerCount)
    {
        if (playerCount <= 4) return 1;
        if (playerCount <= 8) return 2;
        return 3;
    }

    public static RoomConfig Create(SeatConfig[] seats)
    {
        int n = seats.Length;
        return new RoomConfig(n, CalcDeckCount(n), seats);
    }
}
