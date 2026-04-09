using UnityEngine;
using UnityEngine.UI;

public class ResultView : MonoBehaviour
{
    [SerializeField] private Text _content = null!;

    private void OnEnable()
    {
        GameEvents.OnRoundDone += HandleRoundDone;
    }

    private void OnDisable()
    {
        GameEvents.OnRoundDone -= HandleRoundDone;
    }

    private void HandleRoundDone(int[] scores)
    {
        _content.text = string.Join("
", scores);
    }
}
