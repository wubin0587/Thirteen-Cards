# 福建十三水 · Unity 前端架构文档

> 版本 v0.1 · 覆盖范围：3~12人局、自由配置电脑玩家、横竖屏自适应

---

## 目录

1. [项目总览](#1-项目总览)
2. [目录结构](#2-目录结构)
3. [Scene 清单](#3-scene-清单)
4. [脚本文件清单与职责](#4-脚本文件清单与职责)
   - 4.1 [Core — 跨场景核心](#41-core--跨场景核心)
   - 4.2 [Room — 房间配置](#42-room--房间配置)
   - 4.3 [Game — 游戏主场景](#43-game--游戏主场景)
   - 4.4 [UI — 通用组件](#44-ui--通用组件)
   - 4.5 [Native — C++ 绑定层](#45-native--c-绑定层)
   - 4.6 [AI — Sentis 推理层](#46-ai--sentis-推理层)
   - 4.7 [Net — 联机通信层](#47-net--联机通信层)
   - 4.8 [VFX — 特效与音效](#48-vfx--特效与音效)
   - 4.9 [Layout — 响应式布局](#49-layout--响应式布局)
5. [Prefab 清单](#5-prefab-清单)
6. [ScriptableObject 数据定义](#6-scriptableobject-数据定义)
7. [玩家槽位系统（3~12人 · 电脑/真人混配）](#7-玩家槽位系统312人--电脑真人混配)
8. [横竖屏自适应方案](#8-横竖屏自适应方案)
9. [数据流与调用链](#9-数据流与调用链)
10. [状态机定义](#10-状态机定义)
11. [关键接口约定](#11-关键接口约定)

---

## 1 项目总览

| 维度 | 说明 |
|------|------|
| 引擎 | Unity 2022 LTS (C#) |
| UI 系统 | UGUI（主 UI）+ UI Toolkit（设置/调试面板） |
| 本地 AI | Unity Sentis —— 加载 `rl_ranker.onnx`，设备端推理 |
| 原生逻辑 | C++ 共享库（`.so/.dylib/.dll`），P/Invoke 调用 `manager.h` C API |
| 联机 | WebSocket（Phase 4，本文预留接口，不展开实现） |
| 目标平台 | Android（主）· iOS · PC Standalone |
| 玩家配置 | 3~12 人，任意位置可设为电脑玩家（AI Bot） |
| 屏幕方向 | 竖屏优先，运行时可切横屏，UI 自动重排 |

### 副牌规则对照

| 人数 | 副牌数 | 总张数 | 备注 |
|------|--------|--------|------|
| 3~4  | 单副   | 52 张  | 标准牌局 |
| 5~8  | 双副   | 104 张 | 五同等多副专属牌型生效 |
| 9~12 | 三副   | 156 张 | 超大牌局，同点最多 12 张 |

副牌数由 `RoomConfig.DeckCount` 根据 `PlayerCount` 自动计算，`NativeGameCore` 传递给 C++ `round_init`。

---

## 2 目录结构

```
Assets/
├── Scenes/
│   ├── Boot.unity              # 启动场景，加载全局单例
│   ├── MainMenu.unity          # 主菜单 / 大厅
│   ├── RoomSetup.unity         # 房间配置（人数、位置、AI/真人）
│   ├── Game.unity              # 游戏主场景
│   └── Result.unity            # 结算场景
│
├── Scripts/
│   ├── Core/                   # 跨场景核心，DontDestroyOnLoad
│   ├── Room/                   # 房间配置逻辑
│   ├── Game/                   # 游戏流程与玩法
│   │   ├── State/              # 游戏状态机
│   │   ├── Player/             # 玩家槽位系统
│   │   ├── Hand/               # 手牌 / 墩位交互
│   │   └── Score/              # 结算逻辑
│   ├── UI/                     # 通用 UI 组件
│   ├── Native/                 # C++ P/Invoke 绑定
│   ├── AI/                     # Sentis 推理封装
│   ├── Net/                    # WebSocket 联机（Phase 4 预留）
│   ├── VFX/                    # 特效 / 音效触发
│   └── Layout/                 # 横竖屏响应式布局
│
├── Prefabs/
│   ├── Card/
│   ├── Player/
│   ├── UI/
│   └── VFX/
│
├── ScriptableObjects/
│   ├── GameSettings.asset
│   ├── CardDatabase.asset
│   └── DifficultyPresets.asset
│
├── StreamingAssets/
│   └── rl_ranker.onnx          # AI 推理模型
│
├── Resources/
│   ├── Textures/Cards/         # 扑克牌正面贴图（52+背面）
│   └── Audio/
│
└── ThirdParty/
    ├── Plugins/                # thirteen_cards_cpp.so / .dll / .dylib
    └── DOTween/
```

---

## 3 Scene 清单

### Boot.unity

**职责：** 初始化全局单例，加载持久化数据，跳转主菜单。  
**存活对象：** `GameManager`、`AudioManager`、`LayoutManager`、`NativeGameCore`（P/Invoke 初始化）、`SentisInferenceRunner`（预热模型）。  
**加载时机：** 应用启动时自动加载，仅执行一次。

---

### MainMenu.unity

**职责：** 显示主菜单按钮（单机游戏、联机、设置、退出），展示玩家战绩。  
**关键 UI：** `MainMenuPanel`、`StatsBoardPanel`、`SettingsPanel`。  
**跳转：** 点击"单机游戏"→ `RoomSetup.unity`；点击"联机"→ `RoomSetup.unity`（联机模式）。

---

### RoomSetup.unity

**职责：** 配置本局参数：玩家数（3~12）、每个座位选真人或 AI Bot（含难度）、副牌数预览。  
**关键组件：** `RoomSetupController`、`SeatSlotPanel`（×12）、`PlayerCountSlider`。  
**输出：** 生成 `RoomConfig` ScriptableObject 实例，传入 `Game.unity`。

---

### Game.unity

**职责：** 游戏主场景，包含完整一局的所有阶段：发牌、理牌、翻牌、结算动画。  
**关键组件：** `GameStateMachine`、`TableController`、`HandAreaController`、`TimerController`、`VFXDirector`。

---

### Result.unity

**职责：** 展示本局所有玩家的水数排名、打枪/全垒打成就、累计总分，提供"再来一局"和"返回大厅"按钮。  
**数据来源：** `SessionResult`（从 `GameStateMachine` 传递）。

---

## 4 脚本文件清单与职责

### 4.1 Core — 跨场景核心

#### `GameManager.cs`
- **模式：** 单例，`DontDestroyOnLoad`
- **职责：**
  - 持有当前 `RoomConfig`（玩家数、座位配置、副牌数）
  - 驱动 Scene 跳转（`LoadScene`封装）
  - 管理游戏全局状态枚举 `AppState`（Menu / RoomSetup / InGame / Result）
  - 存储跨局累计积分 `PlayerTotalScores[]`

#### `AudioManager.cs`
- **模式：** 单例，`DontDestroyOnLoad`
- **职责：**
  - 播放 BGM（循环）、音效（一次性）
  - 提供 `PlaySFX(SFXType)` 统一接口
  - 音量持久化（PlayerPrefs）

#### `SaveDataManager.cs`
- **模式：** 单例
- **职责：**
  - JSON 序列化/反序列化玩家档案（总胜场、水数、成就）
  - 路径：`Application.persistentDataPath/save.json`

---

### 4.2 Room — 房间配置

#### `RoomSetupController.cs`
- **挂载：** `RoomSetup.unity` 根节点
- **职责：**
  - 监听玩家数滑动条变化（3~12），动态显示/隐藏座位槽
  - 根据人数自动计算并显示副牌数（`DeckCountLabel`）
  - 收集所有 `SeatSlotPanel` 的配置，构造 `RoomConfig`
  - 点击"开始游戏"触发 Scene 跳转

#### `SeatSlotPanel.cs`
- **挂载：** 每个座位 UI 面板（最多 12 个）
- **职责：**
  - 切换座位类型：**空位（灰）/ 真人（蓝）/ AI Bot（橙）**
  - AI Bot 情况下显示难度下拉框（Easy / Medium / Hard / Expert）
  - 对 seat 0（本机玩家）：强制为真人，不可修改
  - 暴露 `SeatConfig GetConfig()` 供 `RoomSetupController` 收集

#### `RoomConfig.cs`（ScriptableObject 实例，运行时创建）
- **字段：**
  ```csharp
  int PlayerCount;           // 3~12
  int DeckCount;             // 自动计算：1/2/3
  SeatConfig[] Seats;        // 长度 = PlayerCount
  bool IsOnline;             // 联机模式标志
  string RoomCode;           // 联机房间码（离线时为空）
  ```

#### `SeatConfig.cs`（数据类）
- **字段：**
  ```csharp
  int SeatIndex;
  SeatType Type;             // Human / Bot / Empty
  BotDifficulty Difficulty;  // Easy/Medium/Hard/Expert（Bot时有效）
  string PlayerName;
  string AvatarId;
  ```

---

### 4.3 Game — 游戏主场景

#### `GameStateMachine.cs`
- **挂载：** Game.unity 根节点
- **职责：** 驱动一局完整生命周期，详见[第 10 节状态机定义](#10-状态机定义)
- **状态列表：** `Idle → Dealing → Arranging → Revealing → Settling → Finished`
- **依赖：** `NativeGameCore`、`TableController`、`TimerController`、`VFXDirector`

#### `TableController.cs`
- **挂载：** `Table` GameObject
- **职责：**
  - 管理桌面上所有玩家的 UI 占位（头像区、牌背区、结果区）
  - 根据 `RoomConfig.PlayerCount` 和屏幕方向动态定位各玩家视图
  - 调用 `PlayerSlotView.SetupSlot(SeatConfig)` 初始化每个槽位
  - 接收 `GameStateMachine` 事件，驱动各槽位动画（发牌飞入、翻牌、结算高亮）

#### `PlayerSlotView.cs`
- **挂载：** `PlayerSlotPrefab` 上
- **职责：**
  - 显示头像、名称、水数标签、思考状态（旋转指示器）
  - 管理对手的牌背展示（理牌中）和牌面展示（翻牌后）
  - 触发打枪/全垒打特效锚点
  - **对 Bot 玩家：** 显示难度图标，模拟"思考"延迟动画（`BotThinkingDelay`）

#### `HandAreaController.cs`
- **挂载：** `HandArea` GameObject（仅本机玩家使用）
- **职责：**
  - 接收 `NativeGameCore.DealHand()` 返回的 13 张牌
  - 扇形展开 13 张牌（`CardView` Prefab），计算每张牌的旋转和位移
  - 管理牌的选中状态（触摸上浮 +20px，再次触摸取消选中）
  - 提供 `SelectCard(int idx)` / `DeselectCard(int idx)` 接口

#### `PileZoneController.cs`
- **挂载：** `PileZoneArea` GameObject
- **职责：**
  - 管理三个墩位区域（头墩3槽 / 中墩5槽 / 尾墩5槽）
  - 接收从 `HandAreaController` 拖拽过来的 `CardView`
  - 拖入时调用 `NativeGameCore.SetCardToPile(position, cardId)` 验证合法性
  - 检测倒水：当三墩均满时调用 `NativeGameCore.CheckFoul()`，倒水时槽位边框变红
  - 实时显示每墩的牌型名称标签（`HandNameLabel`）

#### `DragHandler.cs`
- **挂载：** `CardView` Prefab
- **职责：**
  - 实现 `IDragHandler`、`IBeginDragHandler`、`IEndDragHandler`、`IDropHandler`
  - 拖拽时牌移至最顶层 Canvas，跟随手指/鼠标
  - 放入目标墩位槽时通知 `PileZoneController`
  - 放入非法位置时弹回原位（`DOTween` 缓动）

#### `TimerController.cs`
- **职责：**
  - 理牌倒计时（默认 60 秒，可配置）
  - 驱动圆环进度条 `fillAmount`（`DOTween`）
  - 最后 10 秒变红 + 心跳声
  - 超时自动触发贪心提交（`BotDecisionEngine.GreedyAction`）

#### `CardView.cs`
- **挂载：** `CardPrefab`
- **职责：**
  - 根据 `CardId` 设置正面贴图（从 `CardDatabase` 查表）
  - 翻牌动画（Y 轴旋转 180°，`DOTween`）
  - 已放入墩位时变灰（`CanvasGroup.alpha = 0.5`）
  - 支持横竖屏尺寸切换（`LayoutManager` 驱动 `RectTransform`）

#### `BotDecisionEngine.cs`
- **挂载：** `GameStateMachine` 同节点
- **职责：**
  - 统一管理所有 Bot 玩家的决策
  - 根据 `SeatConfig.Difficulty` 调用不同策略：
    - Easy/Medium：`NativeGameCore.DFSEnumCombos()` + 随机/贪心选择
    - Hard/Expert：`SentisInferenceRunner.Infer()` 返回 combo 索引
  - 模拟思考延迟（`BotThinkDelay`，随难度变化：Easy 0.5~2s，Expert 0.3~0.8s）
  - 批量为所有 Bot 决策，结果存入 `BotActions[]`

---

### 4.4 UI — 通用组件

#### `ScorePanel.cs`
- **职责：** 显示当前局各玩家水数，支持动态数字滚动动画（`DOTween`）

#### `ActionBar.cs`
- **挂载：** 操作栏底部 UI
- **职责：**
  - "一键理牌"按钮：触发 `SentisInferenceRunner.Infer()` → 弹出方案卡片
  - "撤销"按钮：调用 `NativeGameCore.Undo()`，恢复上一步操作
  - "确认提交"按钮：校验三墩全满后调用 `GameStateMachine.PlayerSubmit()`
  - 根据游戏状态动态启用/禁用按钮

#### `AIProposalPanel.cs`
- **职责：**
  - 显示 AI 推荐的最多 3 套理牌方案（卡片列表）
  - 每张方案卡显示：头墩牌型 / 中墩牌型 / 尾墩牌型 / 总水数预估 / 进攻/防守倾向
  - 点击某方案 → 自动填入三个墩位区域（动画），手牌区对应牌变灰

#### `CountdownRing.cs`
- **职责：** 圆形倒计时 UI，绑定 `TimerController.OnTick` 事件

#### `ResultPanel.cs`
- **挂载：** Result.unity
- **职责：**
  - 展示所有玩家排名、每人各墩得分明细、总水数
  - 高亮打枪/全垒打玩家行（金色边框）
  - "再来一局"按钮：复用当前 `RoomConfig` 重新进入 Game.unity
  - "返回大厅"按钮：跳转 MainMenu.unity

#### `ToastNotification.cs`
- **职责：** 全局浮动提示（倒水警告、特殊牌型提示、网络断线提示）

---

### 4.5 Native — C++ 绑定层

#### `NativeGameCore.cs`
- **模式：** 单例，`DontDestroyOnLoad`（Boot 初始化）
- **职责：** 所有 C++ P/Invoke 调用的唯一入口，隔离平台差异
- **核心方法（对应 manager.h C API）：**

```csharp
// 发牌
void DealRound(int playerCount);

// 获取本机玩家手牌（13张 cardId）
int[] GetMyHand();

// 枚举合法组合（DFS，返回 Top-K）
DFSCandResultManaged DFSEnumCombos(int[] hand13, int maxK = 64);

// 设置某墩位的牌
int SetPile(int position, int[] cards);

// 检测倒水（三墩全满时调用）
bool CheckFoul();

// 撤销上一次墩位操作
bool Undo();

// 提交本机玩家的三墩（理牌完成）
bool SubmitHand(int[] head, int[] middle, int[] tail);

// 结算（关闭本局，返回所有玩家净水数）
int[] CloseRound();

// 单独牌型查询（UI 实时提示用）
HandResultManaged SearchPattern(int position, int[] cards);
```

- **托管数据类：**

```csharp
public class DFSCandResultManaged {
    public bool IsSpecial;
    public int SpecialScore;
    public string SpecialName;
    public HandComboManaged[] Combos;
}

public class HandComboManaged {
    public int UnitCount;
    public HandUnitManaged[] Units;
    public int TypedScore;
    public int[] LooseCards;
}

public class HandResultManaged {
    public int Position;
    public string HandName;
    public int RankOrder;
    public int Score;
}
```

#### `CardUtils.cs`
- **职责：** 纯 C# 实现的牌号工具（`CardRank`、`CardSuit`、`CardName`），用于 UI 展示，不调用 C++

---

### 4.6 AI — Sentis 推理层

#### `SentisInferenceRunner.cs`
- **模式：** 单例，`DontDestroyOnLoad`
- **职责：**
  - 启动时从 `StreamingAssets/rl_ranker.onnx` 加载模型
  - 提供 `Infer(hand13, dfsResult, temperature, aggression)` 接口
  - 内部负责特征编码（`FeatureEncoder`）→ 填充 `TensorFloat` → 执行推理 → 解析 logits
  - 返回 `InferResult`（含 top-3 combo 索引及其评分）
  - 支持异步推理（`InferAsync`），不阻塞主线程

#### `FeatureEncoder.cs`
- **职责：** C# 实现的特征编码，对齐 Python 端 `features.py` 规格
  - `EncodeHand(int[] hand13)` → `float[13, 17]`（`CARD_DIM=17`，多副牌兼容）
  - `EncodeCombos(HandComboManaged[] combos, int[] hand13)` → `float[MAX_COMBOS, 74]`（`COMBO_DIM=74`）
  - `BuildMask(int nValid)` → `float[128]`（`MAX_COMBOS=128`）

#### `DifficultyMapper.cs`
- **职责：** 将 `BotDifficulty` 枚举映射为 `(temperature, aggression)` 参数对

```csharp
public static (float temperature, float aggression) Map(BotDifficulty d) => d switch {
    Easy    => (3.0f, -0.3f),
    Medium  => (1.5f,  0.0f),
    Hard    => (0.5f,  0.3f),
    Expert  => (0.1f,  0.5f),
    _       => (1.5f,  0.0f),
};
```

---

### 4.7 Net — 联机通信层（Phase 4 预留）

#### `WebSocketClient.cs`
- **职责：** WebSocket 连接管理（连接、断线重连、心跳）
- **事件：** `OnConnected`、`OnDisconnected`、`OnMessage<T>`

#### `RoomNetworkManager.cs`
- **职责：**
  - 发送：`CreateRoom`、`JoinRoom`、`SubmitHand`（仅发送本机三墩，不发手牌）
  - 接收：`DealHand`（服务端下发本机手牌）、`AllSubmitted`（广播所有人结果）、`RoundResult`
  - 防作弊：手牌由服务端分发，理牌结果倒计时结束后统一广播

#### `OfflineFallback.cs`
- **职责：** 联机模式下断线时自动切换为本地 Bot 接管，避免卡局

---

### 4.8 VFX — 特效与音效

#### `VFXDirector.cs`
- **挂载：** Game.unity VFX 层（最高 Sort Order Canvas）
- **职责：** 统一触发所有特效，监听 `GameStateMachine` 事件
- **特效触发方法：**

```csharp
// 打枪特效（BiuBiu，触发在赢家头像位置）
void PlayShootEffect(int winnerSeatIndex);

// 全垒打特效（全屏震撼粒子 + 震动）
void PlayHomerunEffect(int winnerSeatIndex);

// 特殊牌型宣告（Banner + 烟花）
void PlaySpecialHandEffect(int seatIndex, string handName);

// 发牌飞入动画（13张依次飞向玩家）
void PlayDealAnimation(int seatIndex, int cardCount);

// 翻牌动画（批量，staggered 时序）
void PlayRevealAnimation(int seatIndex, int[] cardIds);
```

#### `CameraShake.cs`
- **职责：** 全垒打时屏幕震动（Cinemachine Impulse 或手动偏移）

#### `ParticlePool.cs`
- **职责：** 粒子系统对象池，避免频繁 Instantiate

---

### 4.9 Layout — 响应式布局

#### `LayoutManager.cs`
- **模式：** 单例，`DontDestroyOnLoad`
- **职责：**
  - 监听 `Screen.orientation` 变化（+ `OnRectTransformDimensionsChange`）
  - 广播 `OnLayoutChanged(LayoutMode mode)` 事件（`Portrait` / `Landscape`）
  - 提供当前安全区 `SafeArea`（适配刘海屏）

#### `TableLayoutAdapter.cs`
- **挂载：** `TableController` 同节点
- **职责：** 监听 `LayoutManager.OnLayoutChanged`，重新计算各玩家槽位坐标
- **布局策略（详见[第 8 节](#8-横竖屏自适应方案)）**

#### `HandAreaLayoutAdapter.cs`
- **挂载：** `HandAreaController` 同节点
- **职责：** 竖屏时手牌底部横排扇形；横屏时手牌右侧纵排

#### `SafeAreaFitter.cs`
- **挂载：** 顶层 Canvas 子节点
- **职责：** 将 RectTransform 对齐到 `Screen.safeArea`，适配 iOS 刘海 / Android 打孔屏

---

## 5 Prefab 清单

| Prefab | 路径 | 说明 |
|--------|------|------|
| `CardPrefab` | `Prefabs/Card/CardPrefab.prefab` | 单张牌，含正面/背面 Sprite、`CardView`、`DragHandler` |
| `PlayerSlotPrefab` | `Prefabs/Player/PlayerSlotPrefab.prefab` | 对手槽位（头像+牌背+状态标签） |
| `PileSlotPrefab` | `Prefabs/Card/PileSlotPrefab.prefab` | 单个墩位卡槽（含边框、牌型标签） |
| `SeatSlotPanelPrefab` | `Prefabs/UI/SeatSlotPanelPrefab.prefab` | 房间配置界面的单个座位配置面板 |
| `AIProposalCardPrefab` | `Prefabs/UI/AIProposalCardPrefab.prefab` | AI 推荐方案卡片（含三墩预览） |
| `ShootVFXPrefab` | `Prefabs/VFX/ShootVFXPrefab.prefab` | 打枪特效粒子系统 |
| `HomerunVFXPrefab` | `Prefabs/VFX/HomerunVFXPrefab.prefab` | 全垒打全屏特效 |
| `SpecialHandBannerPrefab` | `Prefabs/VFX/SpecialHandBannerPrefab.prefab` | 特殊牌型宣告横幅 |
| `ToastPrefab` | `Prefabs/UI/ToastPrefab.prefab` | 浮动提示 |

---

## 6 ScriptableObject 数据定义

### `GameSettings.asset`

```csharp
[CreateAssetMenu(fileName = "GameSettings", menuName = "TC/GameSettings")]
public class GameSettings : ScriptableObject {
    [Header("时限")]
    public float ArrangeTimeLimit = 60f;    // 理牌时限（秒）
    public float BotThinkDelayMin = 0.3f;
    public float BotThinkDelayMax = 2.0f;

    [Header("副牌规则")]
    public int SingleDeckMaxPlayers = 4;    // ≤4人用单副
    public int DoubleDeckMaxPlayers = 8;    // ≤8人用双副

    [Header("AI")]
    public int DFSMaxK = 64;               // DFS 保留 Top-K
    public string ONNXModelName = "rl_ranker.onnx";

    [Header("网络")]
    public string ServerUrl = "wss://your-server/ws";
    public float HeartbeatInterval = 15f;
    public float ReconnectTimeout = 5f;
}
```

### `CardDatabase.asset`

```csharp
[CreateAssetMenu(fileName = "CardDatabase", menuName = "TC/CardDatabase")]
public class CardDatabase : ScriptableObject {
    public Sprite[] FrontSprites;   // 索引 = CardId % 52（0~51）
    public Sprite BackSprite;
    public string[] CardNames;      // "D2", "C2", ..., "SA"

    public Sprite GetFront(int cardId) => FrontSprites[cardId % 52];
    public string GetName(int cardId)  => CardNames[cardId % 52];
}
```

### `DifficultyPresets.asset`

```csharp
[CreateAssetMenu(fileName = "DifficultyPresets", menuName = "TC/DifficultyPresets")]
public class DifficultyPresets : ScriptableObject {
    public DifficultyParam Easy   = new(3.0f, -0.3f);
    public DifficultyParam Medium = new(1.5f,  0.0f);
    public DifficultyParam Hard   = new(0.5f,  0.3f);
    public DifficultyParam Expert = new(0.1f,  0.5f);
}

[Serializable]
public record DifficultyParam(float Temperature, float Aggression);
```

---

## 7 玩家槽位系统（3~12人 · 电脑/真人混配）

### 槽位索引约定

- **Seat 0** = 本机玩家，固定为人类，永远占据屏幕最下方（竖屏）或左侧（横屏）
- **Seat 1~11** = 其他玩家，可配置为人类（联机）或 Bot（单机）

### 座位类型枚举

```csharp
public enum SeatType { Empty, Human, Bot }
public enum BotDifficulty { Easy, Medium, Hard, Expert }
```

### Bot 决策流程

```
BotDecisionEngine.DecideAll()
    ├─ 对每个 Bot Seat：
    │   ├─ 获取该 Bot 的手牌（NativeGameCore 内部持有）
    │   ├─ DFSEnumCombos(hand13, maxK=64)
    │   ├─ 若特殊牌型 → 直接提交（score = special_score）
    │   └─ 根据难度：
    │       ├─ Easy   → 随机选前 50% 合法 combo
    │       ├─ Medium → 贪心选 typed_score 最大的合法 combo
    │       ├─ Hard   → SentisInferenceRunner.Infer(T=0.5, A=0.3)
    │       └─ Expert → SentisInferenceRunner.Infer(T=0.1, A=0.5)
    └─ 延迟提交（模拟思考时间）
```

### 玩家数与桌面布局映射

| 人数 | 桌面占位方式（竖屏） |
|------|--------------------|
| 3 | 上1 中间0（本机）下空 → 上1、对面1 |
| 4 | 上2 本机下居中 |
| 5 | 上3 本机下居中 |
| 6 | 上3 左右各1 本机下 |
| 7 | 上3 左右各1 下2（含本机） |
| 8 | 上4 左右各1 本机下 |
| 9~12 | 使用 `ScrollablePlayerRack`（可滚动对手区域）+ 固定本机区 |

9人以上对手区域改为横向可滚动列表（`ScrollRect`），头像小型化（`PlayerSlotMini`）。

---

## 8 横竖屏自适应方案

### 核心机制

Unity 层：`Screen.autorotateToPortrait = true`、`Screen.autorotateToLandscapeLeft = true` 均开启。`LayoutManager` 通过 `OnRectTransformDimensionsChange` 回调检测实际旋转，广播 `OnLayoutChanged` 事件。所有需要重排的组件监听此事件，不轮询。

### 竖屏布局（Portrait）

```
┌──────────────────────┐
│   对手区（上部）      │  ← 最多 11 个 PlayerSlotMini 横排/两行
│   桌面公共区（中上）  │  ← 倒计时圆环 + 本局水数
│   我的三墩区（中）    │  ← 头墩(3槽) 中墩(5槽) 尾墩(5槽) 三行
│   手牌区（底部）      │  ← 13张扇形横排
│   操作栏             │  ← 一键理牌 / 撤销 / 提交
└──────────────────────┘
```

### 横屏布局（Landscape）

```
┌──────────────────────────────────────────┐
│ 对手区（上半行，横向紧凑）                │
├──────────┬───────────────────┬───────────┤
│ 我的     │   桌面公共区       │  操作栏   │
│ 手牌区   │   我的三墩区       │  AI推荐   │
│（纵排    │（横向三列）        │  面板     │
│ 左侧）   │                   │           │
└──────────┴───────────────────┴───────────┘
```

### `TableLayoutAdapter` 座位坐标计算

```csharp
void RecalcPositions(LayoutMode mode, int playerCount) {
    float w = safeArea.width, h = safeArea.height;
    // 竖屏：对手均匀分布在上部 80% 宽度区域
    // 横屏：对手均匀分布在上部 30% 高度区域
    for (int i = 1; i < playerCount; i++) {
        slots[i].anchoredPosition = mode == Portrait
            ? CalcPortraitPos(i, playerCount, w, h)
            : CalcLandscapePos(i, playerCount, w, h);
    }
}
```

### 卡牌尺寸自适应

```csharp
// 竖屏：卡宽 = SafeArea.width / 15
// 横屏：卡高 = SafeArea.height / 8
float cardWidth  = mode == Portrait ? safeArea.width / 15f : safeArea.height * 0.6f / 8f;
float cardHeight = cardWidth * 1.4f;  // 长宽比固定 1:1.4
```

---

## 9 数据流与调用链

### 发牌阶段

```
GameStateMachine.EnterDealing()
    → NativeGameCore.DealRound(playerCount)          // C++ tc_round_deal_players
    → NativeGameCore.GetMyHand()                     // C++ tc_player_round 取手牌
    → HandAreaController.SetupHand(int[] hand13)     // 渲染13张牌
    → TableController.ShowCardBacks(allSeats)        // 其他玩家显示牌背
    → VFXDirector.PlayDealAnimation()
    → GameStateMachine.TransitionTo(Arranging)
```

### 理牌阶段（本机玩家）

```
用户拖拽牌 → DragHandler → PileZoneController.TryDrop(position, cardId)
    → NativeGameCore.SetCardToPile(position, cardId)
    → 若三墩全满 → NativeGameCore.CheckFoul()
        ├─ 倒水 → PileZoneController.ShowFoulWarning()
        └─ 合法 → ActionBar.EnableSubmit()

用户点"一键理牌" → ActionBar
    → SentisInferenceRunner.Infer(hand13, dfsResult, T, A)
        → FeatureEncoder.EncodeHand + EncodeCombos
        → Sentis Worker.Execute()
        → 解析 logits → Top-3 combo 索引
    → AIProposalPanel.Show(top3Combos)
    → 用户选方案 → PileZoneController.ApplyCombo(combo)
```

### Bot 决策阶段

```
GameStateMachine.EnterArranging()
    → BotDecisionEngine.DecideAll()  // 协程，非阻塞
        对每个 Bot Seat：
            → NativeGameCore.DFSEnumCombos(botHand13)
            → SentisInferenceRunner.Infer() 或 GreedyAction()
            → await BotThinkDelay
            → BotActions[seatIndex] = chosenCombo
    → 所有 Bot 完成 → GameStateMachine.AllBotsReady()
```

### 结算阶段

```
GameStateMachine.EnterSettling()
    → NativeGameCore.CloseRound()                    // C++ tc_round_close_players
        → 返回 int[] netScores (长度 = playerCount)
    → ScorePanel.AnimateScores(netScores)            // DOTween 数字滚动
    → VFXDirector.PlayShootEffect() / PlayHomerunEffect()
    → SaveDataManager.UpdateStats(netScores)
    → GameStateMachine.TransitionTo(Finished)
    → SceneManager.LoadScene("Result")
```

---

## 10 状态机定义

```
AppState（全局）:  Menu → RoomSetup → InGame → Result → Menu

GameState（局内）:
  Idle
    │ StartGame()
    ▼
  Dealing          发牌动画（约 2s）
    │ DealComplete()
    ▼
  Arranging        理牌阶段，倒计时
    │ AllSubmitted() 或 TimerExpired()
    ▼
  Revealing        翻牌动画（逐座位，staggered）
    │ RevealComplete()
    ▼
  Settling         C++ 结算 + 特效 + 分数动画
    │ SettleComplete()
    ▼
  Finished         跳转 Result Scene
```

每个状态对应 `IGameState` 接口实现（State Pattern）：

```csharp
public interface IGameState {
    void OnEnter(GameStateMachine fsm);
    void OnExit(GameStateMachine fsm);
    void OnUpdate(GameStateMachine fsm);
}
```

---

## 11 关键接口约定

### 事件总线（Event Bus）

所有跨组件通信通过静态事件，避免直接引用：

```csharp
public static class GameEvents {
    // 布局
    public static event Action<LayoutMode> OnLayoutChanged;

    // 游戏流程
    public static event Action<int[]> OnHandDealt;           // arg: hand13
    public static event Action<int, int[]> OnPileUpdated;    // seatIdx, cardIds
    public static event Action<int[]> OnAllSubmitted;        // all seat indices
    public static event Action<int[]> OnRoundResult;         // net scores

    // 特效触发
    public static event Action<int> OnShoot;                 // winner seat
    public static event Action<int> OnHomerun;               // winner seat
    public static event Action<int, string> OnSpecialHand;   // seat, handName
}
```

### C++ 调用错误处理

所有 `NativeGameCore` 方法：返回值 `< 0` 表示错误，映射到 `NativeError` 枚举，通过 `ToastNotification` 展示用户友好提示，同时写入 `Debug.LogError`。

### ONNX 推理失败降级

`SentisInferenceRunner.Infer()` 若抛出异常（模型未加载、张量不匹配），自动降级为 `BotDecisionEngine.GreedyAction()`，确保游戏不中断。

---

*文档由 Claude 自动生成，基于 `manager.h`、`pattern.h`、`models.py`、`rl_train.py` 及 Unity 前端设计方案。如后端接口变更，请同步更新 §4.5 和 §9。*
