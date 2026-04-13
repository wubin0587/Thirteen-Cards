// Scripts/AI/SentisRunner.cs
// Unity Sentis 推理封装。只有 Hard/Expert Bot 和"一键理牌"按钮会调用此处。
// 特征编码对齐 features.py：CARD_DIM=17, COMBO_DIM=74, MAX_COMBOS=128。

using System;
using System.Threading.Tasks;
using UnityEngine;
using Unity.Sentis;

public class SentisRunner : MonoBehaviour
{
    public static SentisRunner Instance { get; private set; }

    [Header("Model Settings")]
    [SerializeField] private ModelAsset _modelAsset;           // Inspector 拖入
    [SerializeField] private BackendType _backend = BackendType.GPUCompute;

    // AI 参数
    private const float HARD_TEMPERATURE   = 0.5f;
    private const float HARD_AGGRESSION    = 0.3f;
    private const float EXPERT_TEMPERATURE = 0.1f;
    private const float EXPERT_AGGRESSION  = 0.5f;

    // 特征维度（与 features.py 完全一致）
    private const int CARD_DIM   = 17;
    private const int COMBO_DIM  = 74;
    private const int MAX_COMBOS = 128;

    private IWorker _worker;
    private bool    _ready = false;

    void Awake()
    {
        if (Instance != null && Instance != this) { Destroy(gameObject); return; }
        Instance = this;
        DontDestroyOnLoad(gameObject);
    }

    void Start()
    {
        LoadModel();
    }

    private void LoadModel()
    {
        try
        {
            if (_modelAsset == null)
            {
                Debug.LogWarning("[SentisRunner] No model asset assigned. AI features disabled.");
                return;
            }

            var model = ModelLoader.Load(_modelAsset);
            _worker = WorkerFactory.CreateWorker(_backend, model);
            _ready  = true;
            Debug.Log("[SentisRunner] ONNX model loaded successfully.");
        }
        catch (Exception e)
        {
            Debug.LogError($"[SentisRunner] Failed to load model: {e.Message}");
            _ready = false;
        }
    }

    // ── 主推理入口（供 BotRunner / ActionBarView 调用）────────────────────────
    /// <summary>
    /// 异步推理，返回推荐的 combo 索引。
    /// 若模型未就绪，回退到贪心（返回 0）。
    /// </summary>
    public async Task<int> InferAsync(int[] hand13, DFSResult dfs, BotDifficulty diff)
    {
        if (!_ready || _worker == null)
        {
            Debug.LogWarning("[SentisRunner] Model not ready, falling back to greedy.");
            return 0;
        }

        float temperature = diff == BotDifficulty.Expert ? EXPERT_TEMPERATURE : HARD_TEMPERATURE;
        float aggression  = diff == BotDifficulty.Expert ? EXPERT_AGGRESSION  : HARD_AGGRESSION;

        try
        {
            // 特征编码
            using var handTensor  = EncodeHand(hand13);
            using var comboTensor = EncodeCombos(dfs, hand13);
            using var maskTensor  = BuildMask(dfs.ComboCount);

            // 执行推理
            _worker.Execute(new Dictionary<string, Tensor>
            {
                ["hand_tokens"]    = handTensor,
                ["combo_features"] = comboTensor,
                ["combo_mask"]     = maskTensor,
            });

            // 读取 logits
            var logitsTensor = _worker.PeekOutput("logits") as TensorFloat;
            if (logitsTensor == null)
            {
                Debug.LogError("[SentisRunner] Output 'logits' not found.");
                return 0;
            }

            // 等待 GPU 完成（Sentis async readback）
            var logitsData = await logitsTensor.ReadbackAndCloneAsync();

            int chosen = SampleFromLogits(logitsData, dfs.ComboCount, temperature);
            logitsData.Dispose();
            return chosen;
        }
        catch (Exception e)
        {
            Debug.LogError($"[SentisRunner] Inference error: {e.Message}");
            return 0;
        }
    }

    // ── 一键理牌：返回推荐的 combo 索引 ──────────────────────────────────────
    public async Task<int> RecommendAsync(int[] hand13, DFSResult dfs)
    {
        // 一键理牌用均衡参数
        int idx = await InferAsync(hand13, dfs, BotDifficulty.Hard);
        GameEvents.FireAIRecommendReady(idx);
        return idx;
    }

    // ── 特征编码：对齐 features.py ────────────────────────────────────────────

    /// <summary>encode_hand(hand13) → (1, 13, 17)</summary>
    private TensorFloat EncodeHand(int[] hand13)
    {
        var data = new float[1 * 13 * CARD_DIM];
        for (int i = 0; i < 13; i++)
        {
            int cardId = hand13[i];
            int rank   = TC.tc_card_rank(cardId);
            int suit   = TC.tc_card_suit(cardId);
            int baseIdx = i * CARD_DIM;

            // suit one-hot [0:4]
            data[baseIdx + suit] = 1f;
            // rank one-hot [4:17]
            data[baseIdx + 4 + rank] = 1f;
        }
        return new TensorFloat(new TensorShape(1, 13, CARD_DIM), data);
    }

    /// <summary>encode_batch_combos(dfs, hand13) → (1, MAX_COMBOS, 74)</summary>
    private TensorFloat EncodeCombos(DFSResult dfs, int[] hand13)
    {
        var data = new float[1 * MAX_COMBOS * COMBO_DIM];

        // 全局手牌统计（供每个 combo 使用）
        var handRankCnt = new float[13];
        var handSuitCnt = new float[13];
        foreach (var c in hand13)
        {
            handRankCnt[TC.tc_card_rank(c)] += 1f;
            handSuitCnt[TC.tc_card_suit(c)] += 1f;
        }

        int n = Mathf.Min(dfs.ComboCount, MAX_COMBOS);
        for (int i = 0; i < n; i++)
        {
            EncodeCombo(dfs.Combos[i], hand13, handRankCnt, handSuitCnt,
                        data, i * COMBO_DIM);
        }

        return new TensorFloat(new TensorShape(1, MAX_COMBOS, COMBO_DIM), data);
    }

    /// <summary>encode_combo 的 C# 翻译，写入 dest[offset..offset+COMBO_DIM]。</summary>
    private void EncodeCombo(
        HandComboManaged combo,
        int[] hand13,
        float[] handRankCnt, float[] handSuitCnt,
        float[] dest, int offset)
    {
        const float MAX_TYPED_SCORE = 30f;

        // [0:3] 全局 combo 统计
        dest[offset + 0] = combo.TypedScore / MAX_TYPED_SCORE;
        dest[offset + 1] = combo.UnitCount  / 3f;
        dest[offset + 2] = combo.LooseCount / 13f;

        // [3:33] 三个 unit，各 10 维
        var units3 = new System.Collections.Generic.List<HandUnitManaged>();
        var units5 = new System.Collections.Generic.List<HandUnitManaged>();
        foreach (var u in combo.Units)
        {
            if (u.CardCount == 3) units3.Add(u);
            else if (u.CardCount == 5) units5.Add(u);
        }
        units5.Sort((a, b) => a.Result.RankOrder.CompareTo(b.Result.RankOrder));

        var orderedUnits = new System.Collections.Generic.List<HandUnitManaged>();
        orderedUnits.AddRange(units3);
        orderedUnits.AddRange(units5);

        for (int ui = 0; ui < 3; ui++)
        {
            int uBase = offset + 3 + ui * 10;
            if (ui >= orderedUnits.Count) continue;  // 留零

            var unit = orderedUnits[ui];
            var cards = unit.Cards;
            var ranks = new int[cards.Length];
            var suits = new int[cards.Length];
            for (int j = 0; j < cards.Length; j++)
            {
                ranks[j] = TC.tc_card_rank(cards[j]);
                suits[j] = TC.tc_card_suit(cards[j]);
            }

            dest[uBase + 0] = unit.CardCount == 3 ? 1f : 0f;
            dest[uBase + 1] = unit.Result.RankOrder / 10f;
            dest[uBase + 2] = unit.Result.Score / 10f;
            dest[uBase + 3] = MaxOf(ranks) / 12f;
            dest[uBase + 4] = MinOf(ranks) / 12f;
            dest[uBase + 5] = UniqueSuitCount(suits) / 4f;

            var rankCnt = new int[13];
            foreach (int r in ranks) rankCnt[r]++;
            dest[uBase + 6] = HasValue(rankCnt, 2) ? 1f : 0f;   // 对子
            dest[uBase + 7] = HasValue(rankCnt, 3) ? 1f : 0f;   // 三条
            dest[uBase + 8] = IsStraight(ranks, unit.CardCount) ? 1f : 0f;
            dest[uBase + 9] = UniqueSuitCount(suits) == 1 ? 1f : 0f;  // 同花
        }

        // [33:52] 散牌统计
        if (combo.LooseCount > 0)
        {
            var lrCnt = new float[13];
            var lsCnt = new float[4];
            int lMax = 0;
            foreach (var c in combo.LooseCards)
            {
                int r = TC.tc_card_rank(c);
                int s = TC.tc_card_suit(c);
                lrCnt[r]++;
                lsCnt[s]++;
                if (r > lMax) lMax = r;
            }
            float maxFreq = Mathf.Max(MaxOfFloat(lrCnt), 1f);
            for (int j = 0; j < 13; j++) dest[offset + 33 + j] = lrCnt[j] / maxFreq;
            for (int j = 0; j < 4; j++)  dest[offset + 46 + j] = lsCnt[j] / combo.LooseCount;
            dest[offset + 50] = lMax / 12f;

            int pairCnt = 0;
            for (int j = 0; j < 13; j++) if (lrCnt[j] >= 2) pairCnt++;
            dest[offset + 51] = pairCnt / 6f;
        }

        // [52:74] 全局手牌统计
        for (int j = 0; j < 13; j++) dest[offset + 52 + j] = handRankCnt[j] / 4f;
        for (int j = 0; j < 4; j++)  dest[offset + 65 + j] = handSuitCnt[j] / 13f;

        bool hasThree = false, hasFour = false, hasStraight = false, hasFlush = false;
        for (int j = 0; j < 13; j++)
        {
            if (handRankCnt[j] >= 3) hasThree = true;
            if (handRankCnt[j] >= 4) hasFour  = true;
        }
        // 顺子检测（5连续点数）
        for (int s = 0; s <= 8; s++)
        {
            bool ok = true;
            for (int k = 0; k < 5; k++) if (handRankCnt[s + k] < 1) { ok = false; break; }
            if (ok) { hasStraight = true; break; }
        }
        if (!hasStraight && handRankCnt[12] >= 1)
        {
            bool ok = true;
            for (int k = 0; k < 4; k++) if (handRankCnt[k] < 1) { ok = false; break; }
            if (ok) hasStraight = true;
        }
        for (int j = 0; j < 4; j++) if (handSuitCnt[j] >= 5) hasFlush = true;

        dest[offset + 69] = hasThree    ? 1f : 0f;
        dest[offset + 70] = hasFour     ? 1f : 0f;
        dest[offset + 71] = hasStraight ? 1f : 0f;
        dest[offset + 72] = hasFlush    ? 1f : 0f;
        dest[offset + 73] = (hasStraight && hasFlush) ? 1f : 0f;
    }

    /// <summary>构造 combo_mask，有效 combo 为 1.0，padding 为 0.0。</summary>
    private TensorFloat BuildMask(int validCount)
    {
        var data = new float[1 * MAX_COMBOS];
        for (int i = 0; i < Mathf.Min(validCount, MAX_COMBOS); i++)
            data[i] = 1f;
        return new TensorFloat(new TensorShape(1, MAX_COMBOS), data);
    }

    // ── 采样（temperature softmax + multinomial）──────────────────────────────
    private int SampleFromLogits(TensorFloat logits, int validCount, float temperature)
    {
        temperature = Mathf.Max(temperature, 1e-3f);
        int n = Mathf.Min(validCount, MAX_COMBOS);

        float maxL = float.NegativeInfinity;
        for (int i = 0; i < n; i++) if (logits[0, i] > maxL) maxL = logits[0, i];

        float sumExp = 0f;
        var probs = new float[n];
        for (int i = 0; i < n; i++)
        {
            probs[i] = Mathf.Exp((logits[0, i] - maxL) / temperature);
            sumExp += probs[i];
        }
        for (int i = 0; i < n; i++) probs[i] /= sumExp;

        // 按概率采样
        float rand = UnityEngine.Random.value;
        float cumsum = 0f;
        for (int i = 0; i < n; i++)
        {
            cumsum += probs[i];
            if (rand <= cumsum) return i;
        }
        return n - 1;
    }

    // ── 工具方法 ─────────────────────────────────────────────────────────────
    private static int MaxOf(int[] arr) { int m = int.MinValue; foreach (int v in arr) if (v > m) m = v; return m; }
    private static int MinOf(int[] arr) { int m = int.MaxValue; foreach (int v in arr) if (v < m) m = v; return m; }
    private static float MaxOfFloat(float[] arr) { float m = float.MinValue; foreach (float v in arr) if (v > m) m = v; return m; }
    private static int UniqueSuitCount(int[] suits) { var set = new System.Collections.Generic.HashSet<int>(suits); return set.Count; }
    private static bool HasValue(int[] cnt, int minVal) { foreach (int v in cnt) if (v >= minVal) return true; return false; }
    private static bool IsStraight(int[] ranks, int cardCount)
    {
        var unique = new System.Collections.Generic.SortedSet<int>(ranks);
        if (unique.Count != cardCount) return false;
        int[] arr = new int[unique.Count]; unique.CopyTo(arr);
        if (arr[arr.Length - 1] - arr[0] == cardCount - 1) return true;
        if (cardCount == 5 && arr[arr.Length - 1] == 12 &&
            arr[0] == 0 && arr[1] == 1 && arr[2] == 2 && arr[3] == 3) return true;
        return false;
    }

    void OnDestroy()
    {
        _worker?.Dispose();
    }
}
