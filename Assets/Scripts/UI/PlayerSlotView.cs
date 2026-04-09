using UnityEngine;
using UnityEngine.UI;

public class PlayerSlotView : MonoBehaviour
{
    [SerializeField] private Text _name = null!;
    [SerializeField] private Text _score = null!;
    [SerializeField] private GameObject _thinking = null!;

    private int _seat;

    public void Init(SeatConfig cfg)
    {
        _seat = cfg.SeatIndex;
        _name.text = cfg.Name;
        _score.text = "0";
        _thinking.SetActive(cfg.Type == SeatType.Bot);
    }

    public void SetScore(int value) => _score.text = value.ToString();

    public void PlayShoot() => Debug.Log($"Seat {_seat} shoot VFX");
    public void PlayHomerun() => Debug.Log($"Seat {_seat} homerun VFX");
}
