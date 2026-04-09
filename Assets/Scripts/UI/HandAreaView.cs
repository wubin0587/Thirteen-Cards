using UnityEngine;

public class HandAreaView : MonoBehaviour
{
    [SerializeField] private CardView[] _cardViews = new CardView[13];
    [SerializeField] private PileZoneView _pileZone = null!;

    private readonly bool[] _selected = new bool[13];

    public void OnCardTapped(int idx)
    {
        var ok = _selected[idx]
            ? GameSession.Instance.DeselectCard(idx)
            : GameSession.Instance.SelectCard(idx);

        if (!ok) return;

        _selected[idx] = !_selected[idx];
        RefreshCard(idx);
    }

    public void OnCardDroppedToPile(int cardIdx, int position)
    {
        var ok = GameSession.Instance.AddToPile(position, cardIdx);
        if (!ok) return;

        _cardViews[cardIdx].MoveToPile(position);
        _pileZone.RefreshLabel(position);
    }

    private void RefreshCard(int idx)
    {
        _cardViews[idx].transform.localPosition = new Vector3(0f, _selected[idx] ? 20f : 0f, 0f);
    }
}
