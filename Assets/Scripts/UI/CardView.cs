using UnityEngine;
using UnityEngine.UI;

public class CardView : MonoBehaviour
{
    [SerializeField] private Image _face = null!;
    [SerializeField] private CanvasGroup _group = null!;

    public int CardId { get; private set; }

    public void Bind(int cardId, Sprite sprite)
    {
        CardId = cardId;
        _face.sprite = sprite;
        _group.alpha = 1f;
    }

    public void SetDim(bool dim) => _group.alpha = dim ? 0.5f : 1f;

    public void MoveToPile(int position)
    {
        Debug.Log($"Move card {CardId} to pile {position}");
        SetDim(true);
    }
}
