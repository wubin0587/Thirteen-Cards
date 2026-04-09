using UnityEngine;

public class SeatManager : MonoBehaviour
{
    [SerializeField] private PlayerSlotView[] _slots = new PlayerSlotView[12];

    public void Setup(RoomConfig cfg)
    {
        for (var i = 0; i < 12; i++)
            _slots[i].gameObject.SetActive(i < cfg.PlayerCount);

        for (var i = 0; i < cfg.PlayerCount; i++)
            _slots[i].Init(cfg.Seats[i]);

        ArrangeSlots(cfg.PlayerCount);
    }

    private void ArrangeSlots(int n)
    {
        for (var i = 0; i < n; i++)
        {
            var rt = _slots[i].GetComponent<RectTransform>();
            rt.anchorMin = rt.anchorMax = CalcAnchor(i, n);
            rt.anchoredPosition = Vector2.zero;
        }
    }

    private static Vector2 CalcAnchor(int seat, int n)
    {
        if (seat == 0) return new Vector2(0.5f, 0.08f);

        var opponents = n - 1;
        var idx = seat - 1;
        if (n <= 6)
            return new Vector2((idx + 1f) / (opponents + 1f), 0.86f);
        if (n <= 10)
        {
            var row = idx % 2;
            var col = idx / 2;
            var cols = (opponents + 1) / 2;
            return new Vector2((col + 1f) / (cols + 1f), row == 0 ? 0.90f : 0.76f);
        }

        if (idx == opponents - 1) return new Vector2(0.08f, 0.52f);
        if (idx == opponents - 2) return new Vector2(0.92f, 0.52f);

        var rem = opponents - 2;
        return new Vector2(((idx % rem) + 1f) / (rem + 1f), idx % 2 == 0 ? 0.90f : 0.76f);
    }
}
