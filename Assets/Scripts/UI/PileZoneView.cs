using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.UI;

public class PileZoneView : MonoBehaviour
{
    [SerializeField] private Text[] _labels = new Text[3];

    public void RefreshLabel(int position)
    {
        var cards = CollectCurrentPileCards(position);
        var cnt = position == 0 ? 3 : 5;
        if (cards.Length < cnt)
        {
            _labels[position].text = string.Empty;
            return;
        }

        var r = TC.tc_search_pattern(position, cards, cnt);
        _labels[position].text = Marshal.PtrToStringAnsi(r.hand_name) ?? string.Empty;
    }

    private int[] CollectCurrentPileCards(int position)
    {
        _ = position;
        return new int[0];
    }
}
