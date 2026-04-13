// Scripts/UI/ResultView.cs
// 结算界面：展示本局水数排名，提供"再来一局"和"返回"按钮。

using System.Linq;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.SceneManagement;

public class ResultView : MonoBehaviour
{
    [Header("Row Template (一条结果行)")]
    [SerializeField] private Transform   _rowContainer;
    [SerializeField] private GameObject  _rowPrefab;    // 含 RankLabel/NameLabel/ScoreLabel

    [Header("Buttons")]
    [SerializeField] private Button _playAgainButton;
    [SerializeField] private Button _backButton;

    [Header("Scene Names")]
    [SerializeField] private string _gameSceneName   = "Game";
    [SerializeField] private string _setupSceneName  = "RoomSetup";

    // ── 生命周期 ─────────────────────────────────────────────────────────────
    void OnEnable()
    {
        GameEvents.OnRoundDone += ShowResults;
    }

    void OnDisable()
    {
        GameEvents.OnRoundDone -= ShowResults;
    }

    void Awake()
    {
        gameObject.SetActive(false);   // 默认隐藏，结算时显示

        _playAgainButton?.onClick.AddListener(() =>
            SceneManager.LoadScene(_gameSceneName));
        _backButton?.onClick.AddListener(() =>
            SceneManager.LoadScene(_setupSceneName));
    }

    // ── 展示结算结果 ─────────────────────────────────────────────────────────
    private void ShowResults(int[] scores)
    {
        gameObject.SetActive(true);

        // 清除旧行
        foreach (Transform t in _rowContainer) Destroy(t.gameObject);

        var session = GameSession.Instance;
        int n = session.Config.PlayerCount;

        // 按本局水数降序排名
        var ranking = Enumerable.Range(0, n)
            .OrderByDescending(i => scores[i])
            .ToArray();

        for (int rank = 0; rank < n; rank++)
        {
            int seat  = ranking[rank];
            int score = scores[seat];
            string name = session.Config.Seats[seat].Name;

            var row = Instantiate(_rowPrefab, _rowContainer);
            var labels = row.GetComponentsInChildren<Text>();

            // 约定 rowPrefab 里 Text 顺序：rank / name / score
            if (labels.Length >= 3)
            {
                labels[0].text = $"#{rank + 1}";
                labels[1].text = name;
                string sign    = score >= 0 ? "+" : "";
                labels[2].text = $"{sign}{score} 水";
                labels[2].color = score >= 0 ? Color.yellow : Color.red;
            }

            // 高亮本机席位（seat 0）
            if (seat == 0)
            {
                var img = row.GetComponent<Image>();
                if (img != null) img.color = new Color(1f, 1f, 0.6f, 0.3f);
            }
        }
    }
}
