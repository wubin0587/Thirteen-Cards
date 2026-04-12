# 福建十三水 · Unity 前端架构（精简版）

> 横屏专用 · 3~12人 · 自由配置电脑玩家

---

## 原则

C++ 后端已实现所有游戏逻辑——牌型判断、合法性校验、选牌/放墩/撤销状态机、结算。  
**Unity 只负责三件事：调 C++ API、渲染画面、响应触摸。**  
不在 C# 里重写任何已有逻辑。

---

## 目录结构

```
Assets/
├── Scenes/
│   ├── Boot.unity
│   ├── RoomSetup.unity
│   ├── Game.unity
│   └── Result.unity
│
├── Scripts/
│   ├── Native/         ← P/Invoke 薄壳，直接映射 manager.h
│   ├── Game/           ← 游戏流程驱动（状态机 + 玩家槽）
│   ├── AI/             ← Sentis 推理封装
│   └── UI/             ← 纯展示组件，无游戏逻辑
│
├── Prefabs/
│   ├── Card.prefab
│   ├── PlayerSlot.prefab
│   └── PileSlot.prefab
│
└── StreamingAssets/
    └── rl_ranker.onnx
```

文件总数目标：**脚本 ≤ 15 个**。

---

## Scene 说明

| Scene | 职责 |
|-------|------|
| `Boot` | 加载 C++ 库、预热 Sentis 模型、跳转 RoomSetup |
| `RoomSetup` | 选人数（3~12）、每个座位配真人/Bot/难度 |
| `Game` | 完整一局：发牌 → 理牌 → 翻牌 → 结算 |
| `Result` | 展示水数排名，"再来一局" / "返回" |

---

## Native 层：P/Invoke 薄壳

**原则：一个函数对一个 C API，不加任何逻辑。**

### `TC.cs`

```csharp
// Scripts/Native/TC.cs
using System.Runtime.InteropServices;

public static class TC
{
    const string LIB = "thirteen_cards_cpp";

    // Cards utils
    [DllImport(LIB)] public static extern int    tc_card_rank(int card_id);
    [DllImport(LIB)] public static extern int    tc_card_suit(int card_id);

    // Pattern / DFS
    [DllImport(LIB)] public static extern int    tc_search_pattern(
        int position, int[] cards, int cnt, out HandResultNative result);
    [DllImport(LIB)] public static extern int    tc_dfs_enum_combos(
        int[] hand13, IntPtr out_result, int max_k);

    // PlayerRound
    [DllImport(LIB)] public static extern IntPtr tc_player_round_create(string name);
    [DllImport(LIB)] public static extern void   tc_player_round_destroy(IntPtr p);
    [DllImport(LIB)] public static extern int    tc_player_round_receive_hand(IntPtr p, int[] hand13);
    [DllImport(LIB)] public static extern int    tc_player_round_set_position(
        IntPtr p, int position, int[] cards, int cnt);
    [DllImport(LIB)] public static extern int    tc_player_round_settle(IntPtr p);
    [DllImport(LIB)] public static extern int    tc_player_round_get_round_score(IntPtr p);
    [DllImport(LIB)] public static extern int    tc_player_round_has_achievement(IntPtr p, int ach);

    // HandManager — 已实现完整的选牌/放墩/撤销状态机
    [DllImport(LIB)] public static extern IntPtr tc_hand_manager_create(int[] hand13);
    [DllImport(LIB)] public static extern void   tc_hand_manager_destroy(IntPtr mgr);
    [DllImport(LIB)] public static extern int    tc_hand_manager_select_card(IntPtr mgr, int idx);
    [DllImport(LIB)] public static extern int    tc_hand_manager_deselect_card(IntPtr mgr, int idx);
    [DllImport(LIB)] public static extern int    tc_hand_manager_add_to_pile(IntPtr mgr, int pos, int idx);
    [DllImport(LIB)] public static extern int    tc_hand_manager_remove_from_pile(IntPtr mgr, int pos, int idx);
    [DllImport(LIB)] public static extern int    tc_hand_manager_undo(IntPtr mgr);
    [DllImport(LIB)] public static extern int    tc_hand_manager_pile_full(IntPtr mgr, int position);
    [DllImport(LIB)] public static extern int    tc_hand_manager_submit(IntPtr mgr, IntPtr pat);

    // Round
    [DllImport(LIB)] public static extern int    tc_round_deal_players(IntPtr[] players, int cnt);
    [DllImport(LIB)] public static extern int    tc_round_close_players(IntPtr[] players, int cnt);
}

// C++ HandResult 的 blittable 镜像
[StructLayout(LayoutKind.Sequential)]
public struct HandResultNative
{
    public int      position;
    public IntPtr   hand_name;   // const char*，用 Marshal.PtrToStringAnsi 读
    public int      rank_order;
    public int      score;
}
```

---

## Game 层：流程驱动

### `GameSession.cs` — 核心文件

**职责：** 持有所有 `PlayerRound` 句柄和本机 `HandManager` 句柄，驱动状态切换，是其他组件唯一的数据来源。

```
状态：Idle → Dealing → Arranging → Revealing → Done
```

```csharp
// Scripts/Game/GameSession.cs
public class GameSession : MonoBehaviour
{
    public static GameSession Instance { get; private set; }

    IntPtr[] _players;      // tc_player_round_t[]
    IntPtr   _handMgr;      // tc_hand_manager_t，本机玩家专用

    public RoomConfig Config  { get; private set; }
    public int[]      MyHand  { get; private set; }   // 13张 cardId，发牌后缓存
    public GamePhase  Phase   { get; private set; }

    // ── 一局开始 ──────────────────────────────────────────
    public void StartRound(RoomConfig cfg)
    {
        Config = cfg;
        _players = new IntPtr[cfg.PlayerCount];
        for (int i = 0; i < cfg.PlayerCount; i++)
            _players[i] = TC.tc_player_round_create(cfg.Seats[i].Name);

        TC.tc_round_deal_players(_players, cfg.PlayerCount);

        // 取回本机手牌（从 PlayerRound 内部读，具体方式见注①）
        MyHand = FetchMyHand();
        _handMgr = TC.tc_hand_manager_create(MyHand);

        Phase = GamePhase.Arranging;
        GameEvents.OnDealDone?.Invoke();
    }

    // ── 本机玩家操作：直接透传给 C++ HandManager ─────────
    // 返回 false 说明 C++ 认为操作非法，UI 不更新
    public bool SelectCard(int idx)              => TC.tc_hand_manager_select_card(_handMgr, idx) == 1;
    public bool DeselectCard(int idx)            => TC.tc_hand_manager_deselect_card(_handMgr, idx) == 1;
    public bool AddToPile(int pos, int idx)      => TC.tc_hand_manager_add_to_pile(_handMgr, pos, idx) == 1;
    public bool RemoveFromPile(int pos, int idx) => TC.tc_hand_manager_remove_from_pile(_handMgr, pos, idx) == 1;
    public bool Undo()                           => TC.tc_hand_manager_undo(_handMgr) == 1;
    public bool IsPileFull(int pos)              => TC.tc_hand_manager_pile_full(_handMgr, pos) == 1;

    // ── 本机提交三墩 ──────────────────────────────────────
    public bool SubmitMyHand()
    {
        // tc_hand_manager_submit 填好 Pattern，再 set_position 写入 PlayerRound
        // （Pattern 是栈上结构体，具体 Marshal 细节按 pattern.h 对齐）
        ...
        return true;
    }

    // ── 结算 ──────────────────────────────────────────────
    public int[] CloseRound()
    {
        TC.tc_round_close_players(_players, Config.PlayerCount);

        var scores = new int[Config.PlayerCount];
        for (int i = 0; i < Config.PlayerCount; i++)
            scores[i] = TC.tc_player_round_get_round_score(_players[i]);

        // 检查成就（打枪/全垒打）
        CheckAchievements(scores);

        Phase = GamePhase.Done;
        return scores;
    }

    void OnDestroy()
    {
        if (_handMgr != IntPtr.Zero) TC.tc_hand_manager_destroy(_handMgr);
        foreach (var p in _players) TC.tc_player_round_destroy(p);
    }
}
```

> **注①**：当前 C API 没有直接取手牌的函数。可在 C++ 侧加一个 `tc_player_round_get_hand(IntPtr p, int[] out13)` 薄包装，或改为在发牌前本机手牌由 `tc_round_deal_players` 后从 deck 偏移量读取。这是唯一需要后端配合补充的接口。

---

### `SeatManager.cs` — 座位布局

**职责：** 按人数激活/隐藏槽位，横屏下计算坐标。

```csharp
// Scripts/Game/SeatManager.cs
public class SeatManager : MonoBehaviour
{
    [SerializeField] PlayerSlotView[] _slots;   // Inspector 预配置 12 个

    public void Setup(RoomConfig cfg)
    {
        for (int i = 0; i < 12; i++)
            _slots[i].gameObject.SetActive(i < cfg.PlayerCount);

        for (int i = 0; i < cfg.PlayerCount; i++)
            _slots[i].Init(cfg.Seats[i]);

        ArrangeSlots(cfg.PlayerCount);
    }

    void ArrangeSlots(int n)
    {
        // 本机(0)：底部中央，固定不动
        // 对手(1~n-1)：上方区域均匀分布
        // n≤6：单行；n≤10：两行；n>10：两行+左右边列
        ...
    }
}
```

座位坐标用锚点百分比，不写死像素。

---

### `BotRunner.cs` — Bot 决策协程

```csharp
// Scripts/Game/BotRunner.cs
public class BotRunner : MonoBehaviour
{
    public async Task DecideAllAsync(GameSession session)
    {
        var tasks = new List<Task>();
        var cfg = session.Config;
        for (int i = 1; i < cfg.PlayerCount; i++)
        {
            if (cfg.Seats[i].Type != SeatType.Bot) continue;
            tasks.Add(DecideOneAsync(session, i, cfg.Seats[i].Difficulty));
        }
        await Task.WhenAll(tasks);
    }

    async Task DecideOneAsync(GameSession session, int seat, BotDifficulty diff)
    {
        int[] hand = session.GetBotHand(seat);

        // DFS 枚举（C++ 已实现，直接调）
        var dfs = DFSHelper.Enumerate(hand, maxK: 32);
        if (dfs.IsSpecial) { session.SubmitBotSpecial(seat); return; }

        int idx = diff switch {
            BotDifficulty.Easy   => Random.Range(0, dfs.ComboCount),
            BotDifficulty.Medium => 0,   // DFS 已降序，0 = 贪心最优
            _                   => await SentisRunner.Instance.InferAsync(hand, dfs, diff),
        };

        await Task.Delay((int)(ThinkDelay(diff) * 1000));
        session.SubmitBotHand(seat, dfs.Combos[idx]);
    }

    static float ThinkDelay(BotDifficulty d) => d switch {
        BotDifficulty.Easy   => Random.Range(1f,   2.5f),
        BotDifficulty.Medium => Random.Range(0.8f, 1.5f),
        BotDifficulty.Hard   => Random.Range(0.5f, 1f),
        BotDifficulty.Expert => Random.Range(0.3f, 0.7f),
        _                    => 1f,
    };
}
```

---

## AI 层：Sentis 推理

### `SentisRunner.cs`

只有 Hard/Expert Bot 和"一键理牌"按钮会走这里，Easy/Medium 不走模型。

```csharp
// Scripts/AI/SentisRunner.cs
public class SentisRunner : MonoBehaviour
{
    public static SentisRunner Instance { get; private set; }
    IWorker _worker;

    void Awake()
    {
        var model = ModelLoader.Load(
            Application.streamingAssetsPath + "/rl_ranker.onnx");
        _worker = WorkerFactory.CreateWorker(BackendType.GPUCompute, model);
    }

    // 返回 combo 索引
    public async Task<int> InferAsync(int[] hand13, DFSResult dfs, BotDifficulty diff)
    {
        var (temp, aggr) = diff == BotDifficulty.Expert ? (0.1f, 0.5f) : (0.5f, 0.3f);

        // 特征编码对齐 features.py（CARD_DIM=17，COMBO_DIM=74，MAX_COMBOS=128）
        using var handT  = EncodeHand(hand13);
        using var comboT = EncodeCombos(dfs, hand13);
        using var maskT  = BuildMask(dfs.ComboCount);

        _worker.Execute(new() {
            ["hand_tokens"]    = handT,
            ["combo_features"] = comboT,
            ["combo_mask"]     = maskT,
        });

        var logits = await (_worker.PeekOutput("logits") as TensorFloat).ReadbackAndCloneAsync();
        return SampleFromLogits(logits, dfs.ComboCount, temp);
    }

    // EncodeHand / EncodeCombos / BuildMask / SampleFromLogits 的实现
    // 直接翻译 features.py 对应函数，约 80 行
}
```

---

## UI 层：纯展示

**原则：UI 组件只读数据和调 `GameSession`，不做任何判断。**

| 文件 | 职责 | 核心依赖 |
|------|------|---------|
| `CardView.cs` | 显示单张牌（正/背面、变灰） | `cardId`、`CardDatabase` |
| `HandAreaView.cs` | 本机手牌横排扇形 + 触摸交互 | `GameSession.Select/AddToPile` |
| `PileZoneView.cs` | 三墩槽位 + 实时牌型标签 | `TC.tc_search_pattern` |
| `PlayerSlotView.cs` | 对手头像、水数、思考动画 | `SeatConfig` |
| `ActionBarView.cs` | 一键理牌 / 撤销 / 提交 | `GameSession` |
| `TimerView.cs` | 倒计时圆环 | `GameSession.TimeLeft` |
| `ResultView.cs` | 结算排名展示 | `CloseRound()` 的 scores |
| `RoomSetupView.cs` | 人数 + 座位配置 | 输出 `RoomConfig` |

### `HandAreaView.cs` 交互逻辑

```csharp
void OnCardTapped(int idx)
{
    // C++ 判断是否可选，返回 0 = 非法，不更新视图
    bool ok = _selected[idx]
        ? GameSession.Instance.DeselectCard(idx)
        : GameSession.Instance.SelectCard(idx);
    if (ok) RefreshCard(idx);
}

void OnCardDroppedToPile(int cardIdx, int position)
{
    bool ok = GameSession.Instance.AddToPile(position, cardIdx);
    if (!ok) return;   // C++ 校验不通过就什么都不做
    _cardViews[cardIdx].MoveToPile(position);
    _pileZone.RefreshLabel(position);
}
```

### `PileZoneView.cs` 牌型实时标签

```csharp
public void RefreshLabel(int position)
{
    int[] cards = CollectCurrentPileCards(position);
    int cnt = position == 0 ? 3 : 5;
    if (cards.Length < cnt) { _labels[position].text = ""; return; }

    // 直接问 C++，不自己判断
    TC.tc_search_pattern(position, cards, cnt, out var r);
    _labels[position].text = Marshal.PtrToStringAnsi(r.hand_name_ptr);
}
```

---

## VFX

不需要独立脚本。`GameSession.CloseRound()` 触发静态事件，`PlayerSlotView` 上的 `Animator` 直接响应：

```csharp
// GameEvents.cs（仅 3 行有效内容）
public static class GameEvents {
    public static event Action          OnDealDone;
    public static event Action<int>     OnShoot;        // 赢家 seat index
    public static event Action<int>     OnHomerun;
    public static event Action<int[]>   OnRoundDone;    // 所有人水数
}
```

---

## 横屏布局

锁定横屏：`Screen.orientation = ScreenOrientation.LandscapeLeft`。

```
┌──────────────────────────────────────────────────────┐
│  对手区（上方，按人数均匀排布）                         │
├──────────┬───────────────────────┬───────────────────┤
│ 本机手牌  │   我的三墩区           │  操作区           │
│ 横排扇形  │   [头墩][中墩][尾墩]   │  ⚡ 一键理牌       │
│ 底部左侧  │   牌型标签实时显示     │  ↩ 撤销           │
│          │                       │  ✓ 提交           │
└──────────┴───────────────────────┴───────────────────┘
```

所有区域用锚点百分比定位，适配不同屏幕尺寸无需额外代码。

人数与对手区排布：

| 人数 | 对手区排布 |
|------|----------|
| 3~6  | 上方单行均匀 |
| 7~10 | 上方两行 |
| 11~12 | 两行 + 左右边列各 1 |

---

## 数据结构（C# 侧，仅两个）

```csharp
public record RoomConfig(
    int          PlayerCount,   // 3~12
    int          DeckCount,     // <=4→1，<=8→2，<=12→3
    SeatConfig[] Seats
);

public record SeatConfig(
    int           SeatIndex,
    SeatType      Type,         // Human / Bot
    BotDifficulty Difficulty,
    string        Name
);
```

其余所有数据结构（牌型、Pattern、DFSResult 等）直接用 C++ 返回值，不在 C# 里重新定义业务含义。

---

## 文件汇总

| 文件 | 预估行数 |
|------|---------|
| `TC.cs` | 60 |
| `GameSession.cs` | 150 |
| `SeatManager.cs` | 70 |
| `BotRunner.cs` | 70 |
| `SentisRunner.cs` | 120 |
| `HandAreaView.cs` | 90 |
| `PileZoneView.cs` | 70 |
| `CardView.cs` | 40 |
| `PlayerSlotView.cs` | 50 |
| `ActionBarView.cs` | 40 |
| `TimerView.cs` | 30 |
| `ResultView.cs` | 50 |
| `RoomSetupView.cs` | 70 |
| `GameEvents.cs` | 15 |
| `RoomConfig.cs` | 20 |
| **合计** | **~935** |

后端 C++ 约 3000 行，前端 C# 约 1000 行，比例合理。

---

## 唯一需要后端补充的接口

当前 `manager.h` 缺少一个取本机手牌的函数：

```cpp
// 建议在 manager.h 补充
int tc_player_round_get_hand(tc_player_round_t player, int out_hand13[13]);
```

其他全部接口已覆盖，前端无需补充任何游戏逻辑。
