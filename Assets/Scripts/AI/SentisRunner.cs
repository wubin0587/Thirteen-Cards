using System.Threading.Tasks;
using UnityEngine;

public class SentisRunner : MonoBehaviour
{
    public static SentisRunner Instance { get; private set; } = null!;

    private void Awake()
    {
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }
        Instance = this;

        // 实际项目中这里加载 Sentis 模型并创建 worker。
        Debug.Log($"Warmup ONNX: {Application.streamingAssetsPath}/rl_ranker.onnx");
    }

    public async Task<int> InferAsync(int[] hand13, DFSResult dfs, BotDifficulty diff)
    {
        _ = hand13;
        await Task.Yield();

        var (temp, aggr) = diff == BotDifficulty.Expert ? (0.1f, 0.5f) : (0.5f, 0.3f);
        Debug.Log($"Sentis Infer temp={temp}, aggr={aggr}, combos={dfs.ComboCount}");

        return Mathf.Clamp(dfs.ComboCount - 1, 0, dfs.ComboCount - 1);
    }
}
