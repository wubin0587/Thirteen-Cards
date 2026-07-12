# 🀄 福建十三水 (Fujian Thirteen Cards) - AI 棋牌游戏

![Flutter](https://img.shields.io/badge/Flutter-3.0+-blue?style=flat-square&logo=flutter)
![C++](https://img.shields.io/badge/C++-17-blue?style=flat-square&logo=c%2B%2B)
![Python](https://img.shields.io/badge/Python-3.8+-yellow?style=flat-square&logo=python)
![PyTorch](https://img.shields.io/badge/PyTorch-RL-ee4c2c?style=flat-square&logo=pytorch)
![ONNX](https://img.shields.io/badge/ONNX-Runtime-005CED?style=flat-square)

本项目是一款基于 **C++ 规则引擎 + Transformer RL AI + Flutter 跨平台客户端** 的【福建十三水】（十三张/十三道）棋牌游戏。
底层采用 C++ 实现牌型判定、DFS 最优摆牌搜索与完整结算逻辑，Python 实现 PPO 自博弈 AI 训练并导出 ONNX 端侧推理，
Flutter 通过 dart:ffi 桥接 C++ 动态库，提供动画化的游戏交互与一键理牌体验。

---

## ✨ 核心特性

### 🎮 纯正的福建十三水玩法
- **多人数自适应**：3~4 人单副牌（52 张），5~8 人自动切换双副牌（104 张），支持五同牌型
- **完整计分体系**：打枪（三墩全胜 ×2）、全垒打（击败所有对手 ×3，优先于打枪）、倒水买单
- **13 种特殊牌型**：至尊清龙、一条龙、三同花顺、三分天下等，自动识别直接结算
- **四种难度**：简单 / 中等 / 困难 / 专家，对应不同的 temperature 与 aggression 参数

### ⚡ C++ 规则引擎（约 3000 行）
- **牌型识别**：10 种常规牌型 + 13 种特殊牌型的级联+DFS 回溯判定，无 STL 纯 C 风格
- **DFS 最优摆牌**：5 阶段枚举（候选生成→独立集搜索→不倒水验证→Top-K 排序），3 种剪枝策略（bitmask 冲突/槽位满/上界），实测 < 5ms
- **完整结算**：9 步骤结算引擎，含全垒打 ×3 优先于打枪 ×2 的正确倍率应用、倒水买单的余数分配
- **统一 C API**：约 50 个函数，不透明句柄模式，14 种细粒度错误码

### 🤖 Transformer + PPO AI 模型
- **策略网络**：2 层 Transformer Encoder + Cross-Attention Scorer，约 85K 参数
- **74 维组合特征**：精确编码 unit/loose/global 三级统计量
- **PPO 自博弈训练**：200K 局、三阶段课程学习（贪心→checkpoint pool→完全 self-play）
- **ONNX 端侧部署**：独立的子进程推理架构，不可用时自动回退 C++ 贪心策略

### 📱 Flutter 跨平台客户端（约 6000 行 Dart）
- **dart:ffi 桥接**：25 个 C 函数绑定 + 3 个核心结构体映射
- **三层容错**：ONNX 推理 → C++ 不倒水验证 → 本地回退
- **交互**：AI 一键理牌（保守/均衡/激进）、手动点击/拖拽摆牌
- **反馈**：渐进发牌动画、逐墩翻牌、TTS 中文语音播报、音效反馈

---

## 🛠️ 技术架构

```
展示层 ─ Flutter (Dart) ─── UI 渲染 · 动画 · 语音 · 设置持久化
    │
    │ dart:ffi
    ▼
业务层 ─ C++ 动态库 ─────── 牌型识别 · DFS 搜索 · 结算 · ONNX 推理封装
    │
    │ ctypes / 离线训练
    ▼
训练层 ─ Python (PyTorch) ─ Transformer 模型 · PPO 自博弈 · ONNX 导出
```

### 设计原则
- **规则唯一性**：所有游戏规则（牌型判定、合法性校验、计分）均在 C++ 侧实现，不做规则复制
- **统一接口**：C++ 通过 `extern "C"` 导出统一 API，供 Dart FFI 和 Python ctypes 调用
- **离线训练**：AI 模型离线训练后导出 ONNX 格式，端侧零延迟推理

---

## 📁 目录结构

```text
📦 Thirteen-Cards-main
├── 📂 cpp/                  # C++ 规则引擎
│   ├── pattern/             # 牌型识别 (searchPattern.cpp) + DFS 搜索 (dfs.cpp)
│   ├── players/             # 玩家与手牌状态管理
│   ├── round/               # 回合结算 (closer.cpp, dealer.cpp)
│   ├── game/                # 统一状态机 (game.h / game.cpp)
│   ├── games/               # 牌类工具 (cards.h)
│   ├── manager.h/cpp        # 🌟 统一 C API 导出层
│   ├── tests/               # C++ 集成测试
│   └── CMakeLists.txt
├── 📂 python/               # AI 训练
│   ├── env.py               # RL 虚拟对局环境 (ctypes 调用 C++ DFS)
│   ├── features.py          # 74 维特征编码
│   ├── models.py            # TransformerRanker / ActorCritic
│   ├── rl_train.py          # PPO + GAE 训练主入口 (200K 局)
│   ├── train.py             # 监督学习 (保留兼容)
│   └── test.py              # 全链路测试 (696 行)
├── 📂 flutter/              # Flutter 跨平台客户端
│   └── lib/src/
│       ├── backend/
│       │   └── thirteen/    # dart:ffi 桥接层 (thirteen_ffi.dart, 1200 行)
│       └── games/thirteen/  # UI 组件
│           ├── controller/  # 状态管理 (ChangeNotifier)
│           ├── ai/          # AI 推理服务 + 策略风格
│           └── widgets/     # 页面与动画组件
└── 📂 docs/                 # 项目文档 (课程报告)
```

---

## 🚀 快速开始

### 1. 编译 C++ 核心库
```bash
cd cpp
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
cmake --build .
# 输出: build/src/libthirteen_cards_cpp.dll (或 .so)
```

### 2. 运行 Flutter 客户端
```bash
cd flutter
flutter pub get
# 确保 C++ 动态库在运行目录下
flutter run -d windows
```

### 3. AI 模型训练（可选）
```bash
cd python
pip install torch numpy onnx onnxruntime
python rl_train.py --all
# 训练完成后: models/rl_ranker.onnx
```

### 4. 运行测试
```bash
# C++ 集成测试
cd cpp/build
ctest

# Flutter 合约测试
cd flutter
flutter test

# Python 全链路测试
cd python
python test.py
```

---

## 🧪 测试覆盖

| 层级 | 测试文件 | 类型 | 验证内容 |
|------|---------|------|---------|
| C++ | game_flow_test.cpp | 集成 | 完整游戏流程 + net_sum=0 零和约束 |
| Flutter | native_contract_test.dart | 合约 | FFI 接口可用性与阶段转换 |
| Flutter | controller_contract_test.dart | 合约 | AI 回退路径 |
| Python | test.py (696 行) | 单元+集成+回归+性能 | 全模块覆盖 |

---

## 📄 参考文献

- Vaswani et al., "Attention is All You Need", NeurIPS 2017.
- Schulman et al., "Proximal Policy Optimization Algorithms", arXiv 2017.
- Schulman et al., "High-Dimensional Continuous Control Using Generalized Advantage Estimation", ICLR 2016.
- Silver et al., "Mastering Chess and Shogi by Self-Play with a General Reinforcement Learning Algorithm", arXiv 2017.
- Brown & Sandholm, "Superhuman AI for Multiplayer Poker", Science 2019.
- Microsoft, "ONNX Runtime", https://github.com/microsoft/onnxruntime

---

## ⚠️ 免责声明
本项目仅供技术研究与学习交流使用。**严禁将本项目源码及编译产物用于任何形式的非法赌博活动。**
