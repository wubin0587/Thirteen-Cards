# 🎴 福建十三水（Thirteen Cards）

基于 **C++ 核心规则引擎 + Unity 前端** 的福建十三水项目。当前仓库重点是：

- C++ 已实现并导出完整对局规则能力（牌型判断、摆墩合法性、结算、打枪/全垒打判定、交互状态机）。
- Unity 侧按 `unity.md` 的思路搭建“薄前端”：主要负责调用 C++ API、渲染 UI、驱动流程。
- Python 目录包含模型/训练相关代码骨架与实验脚本。

---

## 当前实现状态（按仓库现状）

### ✅ 已完成

#### 1) C++ 核心规则库
- 统一 C API 导出（`manager.h`）已具备：
  - 牌面工具（点数/花色）
  - Pattern 初始化、分墩设置、排序、牌型搜索
  - DFS 组合枚举
  - `PlayerRound` 生命周期与结算接口
  - `HandManager` 选牌/放墩/撤销状态机
  - Round 发牌与整轮结算
- 规则与回合逻辑模块化拆分到 `cards / pattern / players / round`。

#### 2) Unity 侧核心脚本骨架
- `assets/scripts/native/TC.cs`：P/Invoke 薄壳，直接映射 C API。
- `assets/scripts/game/`：
  - `GameSession` 驱动局内阶段（Dealing/Arranging/Revealing/Done）
  - `SeatManager` 座位布局
  - `BotRunner`、`DFSHelper`、`RoomConfig`、`GameEvents` 等流程脚本
- `assets/scripts/ui/`：房间、手牌区、墩区、行动栏、计时器、结果页等视图脚本。

#### 3) Python 训练/推理代码目录
- 已有环境、训练、模型、特征与测试脚本：`src/python/*.py`。

---

### 🚧 进行中 / 待完善

- Unity 场景资源（如 `Boot / RoomSetup / Game / Result`）与美术预制体仍需在编辑器内持续完善与联调。
- Sentis/ONNX 实际模型接入效果、参数与策略质量需要继续验证。
- 联机服务器（WebSocket/HTTP）与完整账号系统尚未在本仓库落地。
- 工程化（自动化测试、CI、打包发布流程）仍需补充。

---

## 仓库结构

```text
build/
└── libthirteen_cards_cpp.dll

src/
├── cpp/
│   ├── cards/
│   ├── pattern/
│   ├── players/
│   ├── round/
│   ├── manager.h
│   ├── manager.cpp
│   └── CMakeLists.txt
└── python/
    ├── env.py
    ├── rl_train.py
    ├── train.py
    ├── models.py
    └── ...

assets/
└── scripts/
    ├── native/
    ├── game/
    ├── ui/
    └── ai/

unity.md
README.md
```

---

## 开发原则（与 `unity.md` 一致）

1. **C++ 管规则，Unity 管表现。**
2. **C# 不重复实现已有规则逻辑。**
3. **优先通过 Native API 透传操作，减少双端逻辑分叉。**

---

## 后续建议

1. 先打通一个可演示闭环：`RoomSetup -> Game -> Result`。
2. 补齐 Unity 场景与 prefab，并做 3/6/9/12 人布局回归。
3. 用固定种子牌局做 C++ 与 Unity 一致性测试。
4. 再推进 AI 策略质量与联机模块，避免并行过多导致维护压力过大。

---

> 本项目用于游戏开发与技术研究。请勿用于任何非法赌博场景。
