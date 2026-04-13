// Scripts/UI/RoomSetupView.cs
// 房间配置界面：选人数（3~12）、每个座位设置真人/Bot/难度。
// 最终输出 RoomConfig 并加载 Game 场景。

using System;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.SceneManagement;

public class RoomSetupView : MonoBehaviour
{
    [Header("Player Count")]
    [SerializeField] private Slider  _playerCountSlider;   // min=3 max=12
    [SerializeField] private Text    _playerCountLabel;

    [Header("Seat Row Prefab & Container")]
    [SerializeField] private Transform  _seatRowContainer;
    [SerializeField] private GameObject _seatRowPrefab;    // 含 SeatType Dropdown + Difficulty Dropdown + NameInput

    [Header("Deck Info")]
    [SerializeField] private Text _deckInfoLabel;

    [Header("Buttons")]
    [SerializeField] private Button _startButton;
    [SerializeField] private Button _backButton;

    [Header("Scene Names")]
    [SerializeField] private string _gameSceneName  = "Game";
    [SerializeField] private string _bootSceneName  = "Boot";

    // ── 内部缓存 ──────────────────────────────────────────────────────────────
    private SeatRowController[] _seatRows;
    private int _playerCount = 4;

    // ── 初始化 ────────────────────────────────────────────────────────────────
    void Start()
    {
        _playerCountSlider.minValue = 3;
        _playerCountSlider.maxValue = 12;
        _playerCountSlider.wholeNumbers = true;
        _playerCountSlider.value = _playerCount;
        _playerCountSlider.onValueChanged.AddListener(OnPlayerCountChanged);

        _startButton?.onClick.AddListener(OnStartGame);
        _backButton?.onClick.AddListener(() => SceneManager.LoadScene(_bootSceneName));

        BuildSeatRows(_playerCount);
    }

    // ── 人数滑块回调 ─────────────────────────────────────────────────────────
    private void OnPlayerCountChanged(float value)
    {
        _playerCount = Mathf.RoundToInt(value);
        _playerCountLabel.text = $"{_playerCount} 人";

        int deckCount = RoomConfig.CalcDeckCount(_playerCount);
        if (_deckInfoLabel != null)
            _deckInfoLabel.text = $"使用 {deckCount} 副牌（{deckCount * 52} 张）";

        // 激活/隐藏座位行
        for (int i = 0; i < _seatRows.Length; i++)
            _seatRows[i].gameObject.SetActive(i < _playerCount);
    }

    // ── 构建座位行 ────────────────────────────────────────────────────────────
    private void BuildSeatRows(int count)
    {
        foreach (Transform t in _seatRowContainer) Destroy(t.gameObject);

        _seatRows = new SeatRowController[12];
        for (int i = 0; i < 12; i++)
        {
            var row = Instantiate(_seatRowPrefab, _seatRowContainer);
            var ctrl = row.GetComponent<SeatRowController>()
                       ?? row.AddComponent<SeatRowController>();
            ctrl.Init(i, isHumanFixed: i == 0);
            _seatRows[i] = ctrl;
            row.SetActive(i < count);
        }
    }

    // ── 开始游戏 ─────────────────────────────────────────────────────────────
    private void OnStartGame()
    {
        var seats = new SeatConfig[_playerCount];

        // Seat 0：本机玩家，固定为 Human
        seats[0] = new SeatConfig(0, SeatType.Human, BotDifficulty.Easy, "我");

        for (int i = 1; i < _playerCount; i++)
        {
            var ctrl = _seatRows[i];
            seats[i] = new SeatConfig(
                i,
                ctrl.SelectedType,
                ctrl.SelectedDifficulty,
                ctrl.PlayerName
            );
        }

        var config = RoomConfig.Create(seats);

        // 通过 GameSession 单例传入配置，再切场景
        // （GameSession 已 DontDestroyOnLoad）
        // 直接加载 Game 场景，Game 场景的 GameSceneController.Start() 会调 StartRound
        PlayerPrefs.SetInt("PlayerCount", _playerCount);  // 传参备用
        _pendingConfig = config;

        SceneManager.sceneLoaded += OnGameSceneLoaded;
        SceneManager.LoadScene(_gameSceneName);
    }

    private RoomConfig _pendingConfig;

    private void OnGameSceneLoaded(UnityEngine.SceneManagement.Scene scene, LoadSceneMode mode)
    {
        SceneManager.sceneLoaded -= OnGameSceneLoaded;
        if (_pendingConfig != null && GameSession.Instance != null)
            GameSession.Instance.StartRound(_pendingConfig);
    }
}

// ── 单行座位配置控件 ──────────────────────────────────────────────────────────
[RequireComponent(typeof(RectTransform))]
public class SeatRowController : MonoBehaviour
{
    [SerializeField] private Text     _seatIndexLabel;
    [SerializeField] private Dropdown _typeDropdown;         // Human / Bot
    [SerializeField] private Dropdown _difficultyDropdown;   // Easy/Medium/Hard/Expert
    [SerializeField] private InputField _nameInput;

    public SeatType      SelectedType       => (SeatType)(_typeDropdown?.value ?? 1);
    public BotDifficulty SelectedDifficulty => (BotDifficulty)(_difficultyDropdown?.value ?? 0);
    public string        PlayerName         => _nameInput?.text ?? $"玩家{SeatIndex+1}";
    public int           SeatIndex          { get; private set; }

    public void Init(int seatIndex, bool isHumanFixed)
    {
        SeatIndex = seatIndex;

        if (_seatIndexLabel != null)
            _seatIndexLabel.text = seatIndex == 0 ? "你" : $"座位 {seatIndex + 1}";

        if (_nameInput != null)
            _nameInput.text = seatIndex == 0 ? "我" : $"玩家{seatIndex + 1}";

        if (_typeDropdown != null)
        {
            _typeDropdown.interactable = !isHumanFixed;
            _typeDropdown.value = isHumanFixed ? (int)SeatType.Human : (int)SeatType.Bot;
            _typeDropdown.onValueChanged.AddListener(OnTypeChanged);
        }

        UpdateDifficultyVisibility();
    }

    private void OnTypeChanged(int val)
    {
        UpdateDifficultyVisibility();
    }

    private void UpdateDifficultyVisibility()
    {
        bool isBot = SelectedType == SeatType.Bot;
        if (_difficultyDropdown != null)
            _difficultyDropdown.gameObject.SetActive(isBot);
    }
}
