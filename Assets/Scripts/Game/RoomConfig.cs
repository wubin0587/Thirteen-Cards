using System;

public enum SeatType { Human, Bot }
public enum BotDifficulty { Easy, Medium, Hard, Expert }
public enum GamePhase { Idle, Dealing, Arranging, Revealing, Done }

public record RoomConfig(
    int PlayerCount,
    int DeckCount,
    SeatConfig[] Seats
);

public record SeatConfig(
    int SeatIndex,
    SeatType Type,
    BotDifficulty Difficulty,
    string Name
);
