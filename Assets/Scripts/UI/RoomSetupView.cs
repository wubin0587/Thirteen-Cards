using UnityEngine;

public class RoomSetupView : MonoBehaviour
{
    [SerializeField] private int _playerCount = 4;

    public void StartGame()
    {
        var seats = new SeatConfig[_playerCount];
        for (var i = 0; i < _playerCount; i++)
        {
            var isBot = i > 0;
            seats[i] = new SeatConfig(
                i,
                isBot ? SeatType.Bot : SeatType.Human,
                isBot ? BotDifficulty.Medium : BotDifficulty.Easy,
                isBot ? $"Bot {i}" : "You");
        }

        var cfg = new RoomConfig(_playerCount, GuessDeckCount(_playerCount), seats);
        GameSession.Instance.StartRound(cfg);
    }

    private static int GuessDeckCount(int playerCount)
    {
        if (playerCount <= 4) return 1;
        if (playerCount <= 8) return 2;
        return 3;
    }
}
