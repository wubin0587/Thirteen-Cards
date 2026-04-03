这是一份为你量身定制的 **《福建十三水 AI (Python 端) 开发指南》**。

基于你提供的文件结构，Python 端的定位非常清晰：它是 **AI 模型的大脑构建区**、**个性化风格的控制区** 以及 **强化学习的训练场**。它将与你的 C++ 核心逻辑库（通过 `ctypes` 交互）紧密结合。

---

# 🎴 福建十三水 AI 后端 (Python) 开发指南

## 📂 目录结构与架构总览

在 `src/python/` 目录下，4 个核心文件构成了 AI 训练和评估的完整生命周期：
*   🧠 **`models.py`**：基础设施层。定义最基础、最纯粹的 Transformer 神经网络架构。
*   🎭 **`individual.py`**：性格包装层。基于基座模型，衍生出具有不同超参（Temperature, Rank）和打牌风格的“个性化 AI”。
*   🏋️ **`train.py`**：训练车间。实现环境交互、Self-Play（自我博弈）、PPO 算法更新与模型保存。
*   ⚔️ **`test.py`**：竞技场与质检站。不同性格 AI 之间的混战、胜率统计以及极端残局测试。

---

## 📄 核心模块详解

### 1. 🧠 `models.py` (标准模型)
**定位**：纯粹的数学抽象，不包含具体的打牌“性格”，只负责从状态到概率分布的映射。

*   **核心职责**：
    *   **状态嵌入 (State Embedding)**：将 13 张牌转化为特征张量。
    *   **Transformer Encoder**：提取牌型组合之间的上下文关系。
    *   **Actor Head (策略网络)**：输出当前所有“合法摆法”（Action Pool）的概率分布。
    *   **Critic Head (价值网络)**：预估当前这手牌最终的输赢得分（Expected Value）。
*   **开发建议**：
    *   网络必须支持 **Action Masking**（动作掩码）。在计算 Policy 输出的 Softmax 之前，将 C++ 端判定为违规（倒水）动作的 logits 设为 `-inf`，确保模型只在合法动作中做选择。

### 2. 🎭 `individual.py` (个性化模型)
**定位**：AI 的“灵魂”。通过不同的超参（Hyperparameters）将冷冰冰的标准模型包装成有血有肉的玩家。

*   **核心职责**：管理你提到的 `temperature`（激进程度）和 `rank`（难度/实力）。
*   **推荐实现思路**：
    ```python
    from models import BaseTransformer

    class IndividualPlayer:
        def __init__(self, model: BaseTransformer, rank_level: int, temperature: float):
            self.model = model
            self.rank = rank_level        # 决定能看到Top几的优质选项
            self.temperature = temperature # 决定选择时的随机性和冒险性

        def make_decision(self, state, valid_actions):
            # 1. 让基座模型输出所有合法动作的原始 logits
            logits = self.model.forward(state, valid_actions)
            
            # 2. 【Rank 控制】：如果是新手，屏蔽掉价值网络打分最高的那几个神仙摆法
            if self.rank == "NOVICE":
                logits = self._mask_top_k(logits, k=3) 
                
            # 3. 【Temperature 控制】：
            # T < 1: 保守，倾向于稳妥的最高概率动作
            # T > 1: 激进，概率分布变平，敢于尝试次优解拼打枪
            logits = logits / self.temperature
            
            # 4. 采样并返回最终决策
            return sample_from_softmax(logits)
    ```

### 3. 🏋️ `train.py` (模型训练)
**定位**：强化学习的心脏，消耗大量算力让 AI 从零开始“左右互搏”。

*   **核心流程**：
    1.  **加载 C++ 引擎**：使用 `ctypes` 调用你编译好的 `thirteen_cards_cpp.dll/.so`，用于洗牌、发牌和结算算分。
    2.  **自我对弈 (Self-Play)**：实例化 4 个 `models.py` 中的标准模型坐在牌桌上对打。
    3.  **收集轨迹 (Trajectory)**：记录每个回合的 `(State, Action, Reward, LogProb)`。
        *   *关键点*：在这个阶段，你需要定义 Reward Function（奖励函数）。例如：赢一家+1分，被打枪-10分，全垒打+20分。
    4.  **PPO 更新**：每收集几千局数据，进行一次梯度下降，更新模型参数。
    5.  **保存权重**：定期导出 `model_epoch_N.pth`，最终为了 Unity 端导出为 `onnx` 格式。

### 4. ⚔️ `test.py` (测试与验证)
**定位**：检验 AI 是不是真的变聪明了，以及测试“性格参数”是否生效。

*   **常规测试 (ELO 评测)**：
    *   加载不同 epoch 的模型，或者加载 `individual.py` 里的【激进玩家】和【保守玩家】，让他们对战 1000 局，统计平均得分。
*   **极端场景测试 (Unit Test for AI)**：
    *   在这里，**手动构造并注入我们在前面推导出的“最差牌型”**（头道散K/中道散A/尾道三条2）。
    *   测试要求：观察高 Rank AI 在面对这手牌时，是否能做到“断尾求生”（即选出预期得分相对没那么惨的摆法），以及是否会触发“倒水”崩溃报错。

---

## 🚀 日常开发工作流 (Workflow)

1.  **打地基**：先完善 C++ 库，确保 `test.py` 中能用 Python 随机发牌并调用 C++ 正确结算出得分。
2.  **建网络**：在 `models.py` 中写好 PyTorch 网络结构，确保前向传播不报错。
3.  **闭环训练**：运行 `python train.py`，看着 Reward 曲线慢慢上升，AI 从随机乱摆变得越来越像样。
4.  **注入灵魂**：训练出一个强大的基座模型后，在 `individual.py` 里调试 `Temperature` 和 `Rank`，捏脸出 3 个不同难度的 AI。
5.  **导出部署**：在 `test.py` 中确认没问题后，通过 `torch.onnx.export` 导出，扔进 Unity 跑在手机上！
